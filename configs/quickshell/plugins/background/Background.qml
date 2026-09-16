import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import qs.Commons
import qs.Ui

// Adapted from omarchy-shell's Background.qml: same crossfade-reveal
// mechanism, but reads the current wallpaper from wallust's own symlink
// (~/.cache/wal/wallpaper, maintained by scripts/switch-wallpaper.sh)
// instead of Omarchy's theme state directory, and double-click opens this
// repo's wallpaper picker instead of omarchy-theme-bg-switcher. No pending
// theme handoff: Color.qml already watches colors.json on its own and
// reloads independently of the background transition.
Item {
  id: root

  readonly property string home: Quickshell.env("HOME")
  readonly property string currentBackgroundLink: home + "/.cache/wal/wallpaper"

  property string currentBackground: ""
  property string displayedBackground: ""
  property string incomingBackground: ""
  property string oldBackground: ""
  property bool finishingTransition: false
  property int backgroundVersion: 0
  property int revealStartedVersion: -1
  property real revealProgress: 1

  function imageUrl(path) {
    return Util.fileUrl(path)
  }

  function refreshBackground() {
    if (!readlinkProc.running) readlinkProc.running = true
  }

  function setBackground(path, instant) {
    path = String(path || "").trim()
    if (!path || path === currentBackground) return
    currentBackground = path
    backgroundVersion += 1
    revealStartedVersion = -1

    revealAnimation.stop()
    finishingTransition = false

    if (instant || !displayedBackground) {
      oldBackground = ""
      incomingBackground = ""
      displayedBackground = path
      revealProgress = 1
      return
    }

    oldBackground = displayedBackground
    incomingBackground = path
    revealProgress = 0
  }

  function startReveal(panel) {
    if (!incomingBackground) return
    panel.maskReady = true
    if (revealStartedVersion === backgroundVersion) return
    revealStartedVersion = backgroundVersion
    revealAnimation.restart()
  }

  function openSelector() {
    // Same as the Display panel's button: switch-wallpaper.sh with no
    // arguments is the fzf path and needs a terminal this has no way to give
    // it. wallpaper-picker summons the native overlay instead.
    Util.execDetached(Util.shellQuote(Paths.shellScripts + "/wallpaper-picker.sh"))
  }

  Process {
    id: readlinkProc
    command: ["readlink", "-f", root.currentBackgroundLink]
    stdout: StdioCollector {
      onStreamFinished: root.setBackground(String(text || "").trim(), false)
    }
  }

  IpcHandler {
    target: "background"

    function refresh(): void {
      root.refreshBackground()
    }

    function set(path: string): void {
      root.setBackground(path, false)
    }

    function setInstant(path: string): void {
      root.setBackground(path, true)
    }
  }

  NumberAnimation {
    id: revealAnimation
    target: root
    property: "revealProgress"
    from: 0
    to: 1
    duration: 420
    easing.type: Easing.InOutCubic
    onFinished: {
      if (root.incomingBackground) {
        root.displayedBackground = root.currentBackground || root.incomingBackground
        root.finishingTransition = true
      }
      root.revealProgress = 1
    }
  }

  Component.onCompleted: refreshBackground()

  Variants {
    model: Quickshell.screens

    PanelWindow {
      id: panel
      required property var modelData

      screen: modelData
      anchors { top: true; bottom: true; left: true; right: true }
      color: "transparent"
      updatesEnabled: true

      // Hyprland leaves an already-mapped layer surface at its old global
      // position when its monitor moves within the layout, so undocking
      // leaves the wallpaper painting at the previous origin. The guard
      // pulses `remapping` on a settled move, and folding it into `visible`
      // is what unmaps and remaps the surface so the compositor re-places
      // it. See Ui/ScreenMoveRemap.qml.
      ScreenMoveRemap { id: screenGuard; window: panel }
      visible: !screenGuard.remapping

      property bool maskReady: false

      // Decode the wallpaper at the size it is actually drawn at, not at the
      // size it happens to be stored at. Without this, a 3840x2160 wallpaper
      // on a 1920x1080 output is decoded to a full 3840x2160 RGBA buffer —
      // 33 MB, four times the pixels that can ever be shown — and up to three
      // of those exist at once mid-crossfade. Measured: the background alone
      // accounted for 44 MB RSS of the shell's total.
      //
      // Rounded up to the device pixel ratio so a fractional-scaled or
      // HiDPI output still gets a full-resolution decode. PreserveAspectCrop
      // treats sourceSize as a bounding box, so the shorter axis still fills.
      readonly property real outputScale:
        modelData && modelData.devicePixelRatio ? modelData.devicePixelRatio : 1
      readonly property size decodeSize: Qt.size(
        Math.ceil(width * outputScale), Math.ceil(height * outputScale))

      function maybeStartReveal() {
        // NOT gated on root.revealProgress === 0. Each screen's Image
        // decodes asynchronously and independently, so on a >1-screen setup
        // one panel's incomingFrame regularly turns Ready a frame or two
        // after the other's already kicked the shared animation off (its
        // revealProgress is already moving). Bailing here on "already
        // started" used to skip arming *this* panel's own maskReady
        // entirely — its incomingLayer then stayed invisible for the whole
        // 420ms fade and only snapped to the new wallpaper at the very end,
        // i.e. the crossfade only ever visibly played on whichever screen
        // happened to decode first. startReveal() below is itself
        // idempotent (revealStartedVersion guards the actual animation
        // restart), so every panel is safe to call it as soon as its own
        // frame is ready.
        if (!root.incomingBackground || maskReady) return
        if (incomingFrame.status !== Image.Ready) return
        Qt.callLater(function() {
          if (!root.incomingBackground || maskReady) return
          if (incomingFrame.status !== Image.Ready) return
          root.startReveal(panel)
        })
      }

      WlrLayershell.namespace: "quickshell-background"
      WlrLayershell.layer: WlrLayer.Background
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
      exclusionMode: ExclusionMode.Ignore

      Image {
        id: base
        anchors.fill: parent
        source: root.imageUrl(root.displayedBackground)
        sourceSize: panel.decodeSize
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: true
        onStatusChanged: {
          if (status === Image.Ready && root.finishingTransition) {
            root.incomingBackground = ""
            root.oldBackground = ""
            root.finishingTransition = false
          }
        }
      }

      Image {
        id: oldFrame
        anchors.fill: parent
        source: root.imageUrl(root.oldBackground)
        sourceSize: panel.decodeSize
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: false
        smooth: true
        // No mipmaps: sourceSize already decodes to the drawn size, so there
        // is no minification for them to serve, and they cost another third
        // of the texture's memory each.
        visible: root.oldBackground !== "" && root.revealProgress < 1
        onStatusChanged: panel.maybeStartReveal()
      }

      Item {
        id: incomingLayer
        anchors.fill: parent
        visible: root.incomingBackground !== "" && incomingFrame.status === Image.Ready && (root.revealProgress >= 1 || panel.maskReady)
        layer.enabled: root.incomingBackground !== "" && root.revealProgress < 1
        layer.smooth: true
        layer.effect: MultiEffect {
          maskEnabled: true
          maskSource: revealMask
          maskThresholdMin: 0.5
          maskSpreadAtMin: 0.02
        }

        Image {
          id: incomingFrame
          anchors.fill: parent
          source: root.imageUrl(root.incomingBackground)
          sourceSize: panel.decodeSize
          fillMode: Image.PreserveAspectCrop
          asynchronous: true
          cache: false
          smooth: true
          onStatusChanged: panel.maybeStartReveal()
        }
      }

      Item {
        id: revealMask
        anchors.fill: parent
        visible: false
        // Only while a crossfade is running. `layer.enabled: true` allocates a
        // full-screen RGBA framebuffer for as long as it is set, and this mask
        // is consumed by exactly one MultiEffect that is itself only enabled
        // during the reveal — so leaving it on held ~8 MB of FBO permanently
        // to serve a 420 ms animation.
        layer.enabled: root.incomingBackground !== "" && root.revealProgress < 1

        readonly property real slant: -0.18
        readonly property real centerTop: width / 2 - slant * height / 2
        readonly property real centerBottom: width / 2 + slant * height / 2
        readonly property real reach: width / 2 + Math.abs(slant) * height / 2 + 4
        readonly property real spread: reach * root.revealProgress

        Shape {
          anchors.fill: parent
          antialiasing: true
          preferredRendererType: Shape.CurveRenderer
          ShapePath {
            fillColor: "white"
            strokeColor: "transparent"
            startX: revealMask.centerTop - revealMask.spread; startY: 0
            PathLine { x: revealMask.centerTop + revealMask.spread; y: 0 }
            PathLine { x: revealMask.centerBottom + revealMask.spread; y: revealMask.height }
            PathLine { x: revealMask.centerBottom - revealMask.spread; y: revealMask.height }
            PathLine { x: revealMask.centerTop - revealMask.spread; y: 0 }
          }
        }
      }

      Connections {
        target: root
        function onIncomingBackgroundChanged() {
          panel.maskReady = false
          panel.maybeStartReveal()
        }
      }

      MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton
        onDoubleClicked: root.openSelector()
      }
    }
  }
}

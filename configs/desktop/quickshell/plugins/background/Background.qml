import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import qs.Commons
import qs.Ui

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

  // the wedge's own length, between slow and ambient; instant in power saver
  readonly property int wedgeMs: Style.motion.enabled ? 420 : 0
  // palette sync (signature D): the new palette's crossfade starts as the wedge passes the centre
  readonly property real paletteCue: 0.5
  readonly property int edgeWidth: Style.space(2)
  onRevealProgressChanged: if (revealProgress >= paletteCue) Color.syncHold = false

  // every output glitches once as the new wallpaper settles
  signal settled()

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
    // wallust usually lands later; this only catches a palette that beats the wedge
    Color.syncHold = Style.motion.enabled
  }

  function startReveal(panel) {
    if (!incomingBackground) return
    panel.maskReady = true
    if (revealStartedVersion === backgroundVersion) return
    revealStartedVersion = backgroundVersion
    revealAnimation.restart()
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
    duration: root.wedgeMs
    easing.type: Style.motion.ambientEasing
    onFinished: {
      if (root.incomingBackground) {
        root.displayedBackground = root.currentBackground || root.incomingBackground
        root.finishingTransition = true
      }
      root.revealProgress = 1
      Color.syncHold = false
      root.settled()
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

      // hyprland keeps moved layer surfaces at the old origin
      ScreenMoveRemap { id: screenGuard; window: panel }
      visible: !screenGuard.remapping

      property bool maskReady: false

      // decode at drawn size, not stored size
      readonly property real outputScale:
        modelData && modelData.devicePixelRatio ? modelData.devicePixelRatio : 1
      readonly property size decodeSize: Qt.size(
        Math.ceil(width * outputScale), Math.ceil(height * outputScale))

      function maybeStartReveal() {
        // not gated on revealProgress === 0
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

      // everything the glitch captures; the mask stays outside it
      Item {
        id: content
        anchors.fill: parent

        Image {
          id: base
          anchors.fill: parent
          source: Util.fileUrl(root.displayedBackground)
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
          source: Util.fileUrl(root.oldBackground)
          sourceSize: panel.decodeSize
          fillMode: Image.PreserveAspectCrop
          asynchronous: true
          cache: false
          smooth: true
          // no mipmaps: sourceSize already matches the drawn size
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
            source: Util.fileUrl(root.incomingBackground)
            sourceSize: panel.decodeSize
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            cache: false
            smooth: true
            onStatusChanged: panel.maybeStartReveal()
          }
        }
      }

      Item {
        id: revealMask
        anchors.fill: parent
        visible: false
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

      // the wedge's leading edges: 2px accent2 riding the mask, only while it moves
      Shape {
        anchors.fill: parent
        visible: root.incomingBackground !== "" && root.revealProgress < 1 && panel.maskReady
        preferredRendererType: Shape.CurveRenderer
        layer.enabled: visible && Style.fx.glow > 0
        layer.effect: Glow { shadowColor: Color.accent2 }

        ShapePath {
          strokeColor: Color.accent2
          strokeWidth: root.edgeWidth
          fillColor: "transparent"
          startX: revealMask.centerTop - revealMask.spread; startY: 0
          PathLine { x: revealMask.centerBottom - revealMask.spread; y: revealMask.height }
        }
        ShapePath {
          strokeColor: Color.accent2
          strokeWidth: root.edgeWidth
          fillColor: "transparent"
          startX: revealMask.centerTop + revealMask.spread; startY: 0
          PathLine { x: revealMask.centerBottom + revealMask.spread; y: revealMask.height }
        }
      }

      Glitch {
        id: glitch
        anchors.fill: parent
        source: content
      }

      Connections {
        target: root
        function onSettled() { glitch.play() }
      }

      Connections {
        target: root
        function onIncomingBackgroundChanged() {
          panel.maskReady = false
          panel.maybeStartReveal()
        }
      }
    }
  }
}

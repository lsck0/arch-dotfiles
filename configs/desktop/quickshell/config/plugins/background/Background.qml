pragma ComponentBehavior: Bound
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Effects
import qs.Commons
import qs.Ui

Item {
  id: root

  component Wallpaper: Image {
    anchors.fill: parent
    fillMode: Image.PreserveAspectCrop
    asynchronous: true
  }

  readonly property string currentBackgroundLink: Paths.wal + "/wallpaper"

  property string currentBackground: ""
  property string displayedBackground: ""
  property string incomingBackground: ""
  property string oldBackground: ""
  property bool finishingTransition: false
  property int backgroundVersion: 0
  property int revealStartedVersion: -1
  property real revealProgress: 1

  // the change: a feathered slanted wedge opens from the centre over the new image, which settles from a slight
  // zoom while the old one dims; motion off makes it instant
  readonly property int duration: Style.motion.ambient
  readonly property int easing: Easing.InOutCubic
  // the palette follows when the wedge is half open
  readonly property real paletteCue: 0.5
  // horizontal run of the wedge edge per unit of height, leaning right at the top
  readonly property real slant: 0.18
  readonly property int feather: Style.space(56)
  // the mask is a soft gradient, so it renders at a fraction of the output's pixels
  readonly property real maskResolution: 0.5
  readonly property real zoom: 0.04
  readonly property real dim: 0.25
  readonly property int edgeWidth: Math.max(1, Math.round(Style.scale))
  readonly property int edgeGlow: Style.space(14)
  readonly property real edgeAlpha: Style.emphasis.dim
  readonly property real edgeGlowAlpha: 0.3

  readonly property bool revealing: incomingBackground !== "" && revealProgress < 1
  onRevealProgressChanged: if (revealProgress >= paletteCue) Colors.syncHold = false

  function refreshBackground() {
    if (!readlinkProc.running) readlinkProc.running = true
  }

  function setBackground(path) {
    path = String(path || "").trim()
    if (!path || path === currentBackground) return
    currentBackground = path
    backgroundVersion += 1
    revealStartedVersion = -1

    revealAnimation.stop()
    finishingTransition = false

    if (!displayedBackground) {
      oldBackground = ""
      incomingBackground = ""
      displayedBackground = path
      revealProgress = 1
      return
    }

    oldBackground = displayedBackground
    incomingBackground = path
    revealProgress = 0
    Colors.syncHold = Style.motion.enabled
  }

  // an undecodable wallpaper keeps the displayed one and lets the same path be set again
  function abortReveal(path) {
    if (!path || path !== incomingBackground) return
    console.warn("Background: cannot decode", path)
    revealAnimation.stop()
    finishingTransition = false
    incomingBackground = ""
    oldBackground = ""
    currentBackground = displayedBackground
    revealProgress = 1
    Colors.syncHold = false
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
      onStreamFinished: root.setBackground(String(text || "").trim())
    }
  }

  IpcHandler {
    target: "background"

    function set(path: string): void {
      root.setBackground(path)
    }
  }

  NumberAnimation {
    id: revealAnimation
    target: root
    property: "revealProgress"
    from: 0
    to: 1
    duration: root.duration
    easing.type: root.easing
    onFinished: {
      if (root.incomingBackground) {
        root.displayedBackground = root.currentBackground || root.incomingBackground
        root.finishingTransition = true
      }
      root.revealProgress = 1
      Colors.syncHold = false
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

      ScreenMoveRemap { id: screenGuard; window: panel }
      visible: !screenGuard.remapping

      property bool maskReady: false

      readonly property real outputScale:
        modelData && modelData.devicePixelRatio ? modelData.devicePixelRatio : 1
      readonly property size decodeSize: Qt.size(
        Math.ceil(width * outputScale), Math.ceil(height * outputScale))

      readonly property bool revealReady: root.incomingBackground !== "" && !maskReady && incomingFrame.status === Image.Ready

      function maybeStartReveal() {
        if (revealReady) Qt.callLater(function() { if (panel.revealReady) root.startReveal(panel) })
      }

      WlrLayershell.namespace: "quickshell-background"
      WlrLayershell.layer: WlrLayer.Background
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
      exclusionMode: ExclusionMode.Ignore

      Item {
        id: content
        anchors.fill: parent

        Wallpaper {
          source: Util.fileUrl(root.displayedBackground)
          sourceSize: panel.decodeSize
          cache: true
          onStatusChanged: {
            if (status === Image.Ready && root.finishingTransition) {
              root.incomingBackground = ""
              root.oldBackground = ""
              root.finishingTransition = false
            }
          }
        }

        Wallpaper {
          source: Util.fileUrl(root.oldBackground)
          sourceSize: panel.decodeSize
          cache: false
          visible: root.oldBackground !== "" && root.revealProgress < 1
          onStatusChanged: panel.maybeStartReveal()
        }

        Rectangle {
          anchors.fill: parent
          visible: root.oldBackground !== "" && root.revealing && panel.maskReady
          color: Colors.wallpaperShadow
          opacity: root.dim * root.revealProgress
        }

        Item {
          anchors.fill: parent
          visible: root.incomingBackground !== "" && incomingFrame.status === Image.Ready && (root.revealProgress >= 1 || panel.maskReady)
          layer.enabled: root.revealing
          layer.smooth: true
          layer.effect: MultiEffect {
            maskEnabled: true
            maskSource: revealMask
            maskThresholdMin: 0.5
            maskSpreadAtMin: 1
          }

          Wallpaper {
            id: incomingFrame
            source: Util.fileUrl(root.incomingBackground)
            sourceSize: panel.decodeSize
            cache: false
            scale: 1 + root.zoom * (1 - root.revealProgress)
            onStatusChanged: {
              if (status === Image.Error) root.abortReveal(root.incomingBackground)
              else panel.maybeStartReveal()
            }
          }
        }
      }

      // the wedge in a frame rotated by its slant: the core and the two feathers are plain rectangles across it
      Item {
        id: wedge
        anchors.fill: parent
        visible: false

        readonly property real angle: Math.atan(root.slant)
        readonly property real diagonal: Math.hypot(width, height)
        readonly property real reach:
          width / 2 * Math.cos(angle) + height / 2 * Math.sin(angle) + root.feather
        readonly property real half: reach * root.revealProgress
        readonly property real soft: Math.min(root.feather, half)
        readonly property real core: half - soft
        readonly property real edge: half - soft / 2
      }

      Item {
        id: revealMask
        anchors.fill: parent
        visible: false
        layer.enabled: root.revealing
        layer.textureSize: Qt.size(Math.ceil(width * root.maskResolution),
          Math.ceil(height * root.maskResolution))

        Item {
          width: wedge.diagonal
          height: wedge.diagonal
          anchors.centerIn: parent
          rotation: wedge.angle * 180 / Math.PI

          Rectangle {
            x: parent.width / 2 - wedge.core
            width: wedge.core * 2
            height: parent.height
            color: "white"
          }
          Rectangle {
            x: parent.width / 2 - wedge.half
            width: wedge.soft
            height: parent.height
            gradient: Gradient {
              orientation: Gradient.Horizontal
              GradientStop { position: 0; color: "transparent" }
              GradientStop { position: 1; color: "white" }
            }
          }
          Rectangle {
            x: parent.width / 2 + wedge.core
            width: wedge.soft
            height: parent.height
            gradient: Gradient {
              orientation: Gradient.Horizontal
              GradientStop { position: 0; color: "white" }
              GradientStop { position: 1; color: "transparent" }
            }
          }
        }
      }

      // two hairlines on the wedge's half-open edge with a gradient halo instead of a blurred layer; they come in as
      // the wedge opens and are gone when it covers the screen
      Item {
        width: wedge.diagonal
        height: wedge.diagonal
        anchors.centerIn: parent
        rotation: wedge.angle * 180 / Math.PI
        visible: root.revealing && panel.maskReady
        opacity: root.edgeAlpha * (wedge.soft / root.feather) * (1 - root.revealProgress)

        Repeater {
          model: [-1, 1]

          Item {
            required property int modelData
            x: parent.width / 2 + modelData * wedge.edge - width / 2
            width: root.edgeGlow * 2
            height: parent.height

            Rectangle {
              anchors.fill: parent
              visible: Style.fx.glow > 0
              opacity: root.edgeGlowAlpha * Math.min(1, Style.fx.glow)
              gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0; color: Util.alpha(Colors.accent2, 0) }
                GradientStop { position: 0.5; color: Colors.accent2 }
                GradientStop { position: 1; color: Util.alpha(Colors.accent2, 0) }
              }
            }
            Rectangle {
              anchors.horizontalCenter: parent.horizontalCenter
              width: root.edgeWidth
              height: parent.height
              color: Colors.accent2
            }
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
    }
  }
}

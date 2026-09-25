import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Ui

// Short compositor-side handoff while the session finishes starting.
Item {
  id: root

  property bool finished: false
  property real startupProgress: 0

  Timer {
    interval: 1400
    running: true
    onTriggered: root.finished = true
  }

  Variants {
    model: Quickshell.screens

    PanelWindow {
      id: panel
      required property var modelData
      screen: modelData
      visible: !root.finished
      anchors { top: true; bottom: true; left: true; right: true }
      color: Color.background
      exclusionMode: ExclusionMode.Ignore
      WlrLayershell.namespace: "quickshell-startup"
      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

      Column {
        anchors.centerIn: parent
        spacing: Style.spacing.lg

        // Terminal boot line: prompt, wordmark, blinking block caret.
        Row {
          anchors.horizontalCenter: parent.horizontalCenter
          spacing: Style.spacing.sm

          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: ">"
            color: Color.accent
            opacity: Style.emphasis.dim
            font.family: Style.font.family
            font.pixelSize: Style.font.heading
          }

          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "HYPRLAND"
            color: Color.foreground
            font.family: Style.font.family
            font.pixelSize: Style.font.heading
            // headerTracking (+2.4), not displayTracking (-0.5): this is a wide-set wordmark, and display tracking is the tight setting for large numerals.
            font.letterSpacing: Style.headerTracking
            // Accent neon bloom on the boot wordmark.
            layer.enabled: Style.fx.glow > 0
            layer.effect: MultiEffect {
              shadowEnabled: true
              shadowColor: Style.fx.glowColor
              shadowBlur: 1.0
              shadowVerticalOffset: 0
              shadowHorizontalOffset: 0
              blurMax: Style.fx.glowRadius
              autoPaddingEnabled: true
            }
          }

          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "_"
            color: Color.accent
            font.family: Style.font.family
            font.pixelSize: Style.font.heading
            layer.enabled: Style.fx.glow > 0
            layer.effect: MultiEffect {
              shadowEnabled: true
              shadowColor: Style.fx.glowColor
              shadowBlur: 1.0
              shadowVerticalOffset: 0
              shadowHorizontalOffset: 0
              blurMax: Style.fx.glowRadius
              autoPaddingEnabled: true
            }
            SequentialAnimation on opacity {
              running: true
              loops: Animation.Infinite
              PropertyAnimation { to: 1; duration: 0 }
              PauseAnimation { duration: 530 }
              PropertyAnimation { to: 0; duration: 0 }
              PauseAnimation { duration: 530 }
            }
          }
        }

        // Uppercase tracked boot status line.
        Text {
          anchors.horizontalCenter: parent.horizontalCenter
          text: ":: STARTING SESSION"
          color: Color.accent
          opacity: Style.emphasis.dim
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          font.bold: true
          font.letterSpacing: Style.headerTracking
        }

        // Airy gap between the wordmark block and the loader.
        Item { width: 1; height: Style.spacing.xl }

        // Segmented terminal boot loader tied to startup progress.
        BarGauge {
          anchors.horizontalCenter: parent.horizontalCenter
          width: Style.space(220)
          height: Style.space(6)
          segments: 32
          value: root.startupProgress
          color: Color.accent
        }

        // Big glowing progress readout.
        Text {
          anchors.horizontalCenter: parent.horizontalCenter
          text: Math.round(root.startupProgress * 100) + "%"
          color: Color.accent
          font.family: Style.font.family
          font.pixelSize: Style.font.body
          font.bold: true
          font.letterSpacing: Style.displayTracking
          layer.enabled: Style.fx.glow > 0
          layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: Style.fx.glowColor
            shadowBlur: 1.0
            shadowVerticalOffset: 0
            shadowHorizontalOffset: 0
            blurMax: Style.fx.glowRadius
            autoPaddingEnabled: true
          }
        }

        NumberAnimation {
          target: root
          property: "startupProgress"
          from: 0
          to: 1
          duration: 1400
          easing.type: Easing.InOutQuad
          running: true
        }
      }

      // Screen-corner HUD brackets + CRT scanlines on the boot splash.
      HudFrame {}
      Scanlines {}
    }
  }
}

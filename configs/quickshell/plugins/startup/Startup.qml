import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons

// Short compositor-side handoff while the session finishes starting. This is
// intentionally independent of the bar, so a bar/widget failure does not
// bring back a completely black login transition.
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
        spacing: 14

        Text {
          anchors.horizontalCenter: parent.horizontalCenter
          text: "HYPRLAND"
          color: Color.foreground
          font.family: Style.fontFamily
          font.pixelSize: 22
          font.letterSpacing: 4
        }

        Rectangle {
          width: 180
          height: 3
          radius: 2
          color: Color.accent
          anchors.horizontalCenter: parent.horizontalCenter

          Rectangle {
            width: parent.width * 0.32
            height: parent.height
            radius: parent.radius
            color: Color.foreground
            x: (parent.width - width) * root.startupProgress

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
        }
      }
    }
  }
}

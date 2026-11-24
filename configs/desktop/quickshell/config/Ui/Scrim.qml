pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons

// the dim over every screen behind an overlay. Its own layer surfaces: they blur the live screen, while the overlay's
// card above them takes the wallpaper blur like every other shell surface
Variants {
  id: root

  property bool shown: false
  property real progress: 1
  property bool interactive: true

  signal clicked()

  model: Quickshell.screens

  PanelWindow {
    required property var modelData

    screen: modelData
    visible: root.shown
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "quickshell-scrim"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    Rectangle {
      anchors.fill: parent
      color: Colors.scrim
      opacity: root.progress
    }

    MouseArea {
      anchors.fill: parent
      enabled: root.interactive
      onClicked: root.clicked()
    }
  }
}

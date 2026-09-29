import QtQuick

// hyprland keeps layer surfaces at the old spot when a monitor moves, so remap
Item {
  id: root

  required property var window
  readonly property var screen: window ? window.screen : null

  property bool remapping: false

  visible: false

  Timer {
    id: settleTimer
    interval: 200
    onTriggered: root.remapping = true
  }

  // unmap long enough that the compositor does not coalesce it
  Timer {
    interval: 50
    running: root.remapping
    onTriggered: root.remapping = false
  }

  Connections {
    target: root.screen
    function onXChanged() { settleTimer.restart() }
    function onYChanged() { settleTimer.restart() }
  }
}

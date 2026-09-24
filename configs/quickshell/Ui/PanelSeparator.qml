import QtQuick
import qs.Commons

// 1px horizontal divider for panel sections.
Rectangle {
  id: root

  property color foreground: Color.foreground
  property real strength: 0.12

  width: parent ? parent.width : implicitWidth
  implicitWidth: 100
  implicitHeight: 1
  height: 1
  color: Qt.rgba(foreground.r, foreground.g, foreground.b, strength)
}

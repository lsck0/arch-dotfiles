import QtQuick
import qs.Commons

Rectangle {
  id: root

  property color foreground: Color.accent
  property real strength: 0.3

  width: parent ? parent.width : implicitWidth
  implicitWidth: 100
  implicitHeight: 1
  height: 1
  color: Qt.rgba(foreground.r, foreground.g, foreground.b, strength)

  layer.enabled: Style.fx.glow > 0
  layer.effect: Glow {}
}

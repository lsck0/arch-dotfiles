import QtQuick
import qs.Commons

Rectangle {
  id: root

  property color foreground: Colors.accent
  property real strength: 0.3

  width: parent ? parent.width : implicitWidth
  implicitWidth: 100
  implicitHeight: 1
  height: 1
  color: Util.alpha(foreground, strength)

  layer.enabled: Style.fx.glow > 0
  layer.effect: Glow {}
}

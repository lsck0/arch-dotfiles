import QtQuick
import QtQuick.Effects
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

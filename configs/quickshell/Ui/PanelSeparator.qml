import QtQuick
import QtQuick.Effects
import qs.Commons

// 1px neon accent divider for panel sections.
Rectangle {
  id: root

  // Accent by default so the divider reads as a phosphor rule.
  property color foreground: Color.accent
  property real strength: 0.3

  width: parent ? parent.width : implicitWidth
  implicitWidth: 100
  implicitHeight: 1
  height: 1
  color: Qt.rgba(foreground.r, foreground.g, foreground.b, strength)

  // Accent neon bloom turns the hairline into a glowing rule.
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

import QtQuick
import QtQuick.Effects
import qs.Commons

MultiEffect {
  shadowEnabled: true
  shadowColor: Style.fx.glowColor
  shadowBlur: 1.0
  shadowVerticalOffset: 0
  shadowHorizontalOffset: 0
  blurMax: Style.fx.glowRadius
  autoPaddingEnabled: true
}

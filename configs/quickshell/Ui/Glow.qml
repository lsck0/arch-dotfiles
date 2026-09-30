import QtQuick
import QtQuick.Effects
import qs.Commons

// the shell's phosphor halo, used as layer.effect
MultiEffect {
  shadowEnabled: true
  shadowColor: Style.fx.glowColor
  shadowBlur: 1.0
  shadowVerticalOffset: 0
  shadowHorizontalOffset: 0
  blurMax: Style.fx.glowRadius
  autoPaddingEnabled: true
}

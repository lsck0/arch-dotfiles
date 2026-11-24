import QtQuick
import QtQuick.Effects

// fades a layered item through an alpha mask on the item itself, as a fill painted over it cannot match a translucent
// card and shows as a box; threshold 0.5 with spread 1 eases the mask's ramp through smoothstep(0, 1)
MultiEffect {
  maskEnabled: true
  maskThresholdMin: 0.5
  maskSpreadAtMin: 1
}

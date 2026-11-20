import QtQuick
import qs.Commons

// alpha mask fading the last visible row of an overflowing list until it reaches its end
FadeRamp {
  required property ListView list
  readonly property bool overflows: list.contentHeight > list.height + 1

  anchors.fill: list
  reach: Style.row.list
  fadeBottom: list.atYEnd ? 0 : 0.95
  layer.enabled: overflows
  Behavior on fadeBottom { NumberAnimation { duration: Style.motion.base; easing.type: Easing.BezierSpline; easing.bezierCurve: Style.motion.enter } }
}

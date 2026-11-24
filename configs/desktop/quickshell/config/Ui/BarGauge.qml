pragma ComponentBehavior: Bound
import QtQuick
import qs.Commons

Row {
  id: root

  property real value: 0
  property int segments: 12
  property color color: Colors.accent
  property real gap: 1
  // a fast meter fed every frame turns this off: one colour animation per segment lags behind the level
  property bool animated: true
  // a held peak above the level lights its own segment; below 0 there is none
  property real hold: -1

  spacing: gap

  readonly property int litCount: Math.round(Math.max(0, Math.min(1, value)) * segments)
  readonly property int holdIndex: Math.round(Math.max(0, Math.min(1, hold)) * segments) - 1
  // whole pixels per segment, so the gaps fall evenly; the last one takes what the rounding leaves
  readonly property int segmentWidth: Math.floor((width - gap * (segments - 1)) / segments)

  Repeater {
    model: root.segments
    Rectangle {
      required property int index
      width: index === root.segments - 1 ? root.width - (root.segmentWidth + root.gap) * (root.segments - 1) : root.segmentWidth
      height: root.height
      radius: 0
      antialiasing: false
      color: index === root.holdIndex && index >= root.litCount ? Qt.lighter(root.color, 1.5)
             : index >= root.litCount ? Util.alpha(root.color, 0.13)
             : (index === root.litCount - 1 ? Qt.lighter(root.color, 1.5) : root.color)
      Behavior on color {
        enabled: root.animated
        ColorAnimation { duration: Style.motion.fast; easing.type: Style.motion.fastEasing }
      }
    }
  }
}

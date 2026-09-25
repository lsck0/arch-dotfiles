import QtQuick
import qs.Commons

// Horizontal segmented gauge (value 0..1), terminal block style.
Row {
  id: root

  property real value: 0
  property int segments: 12
  property color color: Color.accent
  property real gap: 1

  spacing: gap

  readonly property int litCount: Math.round(Math.max(0, Math.min(1, value)) * segments)

  Repeater {
    model: root.segments
    Rectangle {
      width: (root.width - root.gap * (root.segments - 1)) / root.segments
      height: root.height
      radius: 0
      antialiasing: false
      // lit segments fill accent; the leading (peak) segment glows brighter; rest faint.
      color: index >= root.litCount
             ? Qt.rgba(root.color.r, root.color.g, root.color.b, 0.13)
             : (index === root.litCount - 1 ? Qt.lighter(root.color, 1.5) : root.color)
      Behavior on color { ColorAnimation { duration: 120 } }
    }
  }
}

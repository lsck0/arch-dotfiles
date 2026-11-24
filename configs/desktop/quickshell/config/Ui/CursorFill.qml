import QtQuick
import qs.Commons

// the fill of a list row: the selection under the keyboard cursor, else the hover fill
Rectangle {
  property bool hasCursor: false
  property bool hovered: false

  radius: Style.shape.data
  color: hasCursor ? Colors.menu.selectedBackground : hovered ? Style.hoverFill : "transparent"
  Behavior on color { ColorAnimation { duration: Style.motion.fast; easing.type: Style.motion.fastEasing } }
}

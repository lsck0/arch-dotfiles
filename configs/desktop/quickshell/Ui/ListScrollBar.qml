pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import qs.Commons

// an overflowing list keeps its bar on screen at rest, not only while it scrolls. It sits in the gutter beside
// the list, out of its faded layer and clear of the cursor row
ScrollBar {
  id: scrollBar
  required property ListView list
  // the room the list leaves on its right for the bar
  readonly property int gutter: Style.spacing.xs + Style.spacing.xxs * 3

  parent: list.parent
  anchors.top: list.top
  anchors.bottom: list.bottom
  anchors.left: list.right
  anchors.leftMargin: Style.spacing.xxs
  policy: size < 1 ? ScrollBar.AlwaysOn : ScrollBar.AlwaysOff
  padding: Style.spacing.xxs
  minimumSize: 0.1
  background: Rectangle {
    implicitWidth: Style.spacing.xs + Style.spacing.xxs * 2
    radius: width / 2
    color: Util.alpha(Colors.menu.text, Style.hoverFillAlpha)
  }
  contentItem: Rectangle {
    implicitWidth: Style.spacing.xs
    radius: width / 2
    color: scrollBar.active || scrollBar.hovered ? Colors.menu.text : Colors.textDim
  }
}

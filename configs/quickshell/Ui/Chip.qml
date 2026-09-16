import QtQuick
import qs.Commons

// The one pick-from-a-set chip for panels: font, size, scale, monitor layout,
// power mode, reminder presets. Flat fill, accent tint when selected.
Rectangle {
  id: root

  property string text: ""
  property bool selected: false
  // Paints the hover look for a panel's keyboard cursor.
  property bool hasCursor: false
  property real fontSize: Style.font.caption
  property string fontFamily: Style.font.family
  property real minimumWidth: Style.space(40)

  signal clicked()
  signal hovered(bool isHovered)

  readonly property bool hot: mouse.containsMouse || hasCursor

  implicitWidth: Math.max(minimumWidth, label.implicitWidth + Style.spacing.lg * 2)
  implicitHeight: Style.row.control
  radius: Style.cornerRadius
  color: selected ? Color.menu.selectedBackground
    : mouse.pressed ? Style.pressedFill
    : hot ? Style.hoverFill
    : Style.normalFill

  Behavior on color { ColorAnimation { duration: 100 } }

  Text {
    id: label
    textFormat: Text.PlainText
    anchors.centerIn: parent
    width: Math.min(implicitWidth, root.width - Style.spacing.sm * 2)
    horizontalAlignment: Text.AlignHCenter
    elide: Text.ElideRight
    text: root.text
    color: root.selected ? Color.menu.selectedText : Color.menu.text
    font.family: root.fontFamily
    font.pixelSize: root.fontSize
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: root.clicked()
    onContainsMouseChanged: root.hovered(containsMouse)
  }
}

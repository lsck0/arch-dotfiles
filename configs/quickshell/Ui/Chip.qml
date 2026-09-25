import QtQuick
import QtQuick.Effects
import qs.Commons

// The one pick-from-a-set chip for panels: font, size, scale, monitor layout, power mode, reminder presets.
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

  // Accent outline on hover, matching the kit's other controls; border draws inward so it never shifts the label.
  border.color: Style.hoverBorderColor
  border.width: hot && !selected ? Style.hoverBorderWidth : 0

  Behavior on color { ColorAnimation { duration: 100 } }

  // Subtle tactile press; fires only on the pressed state change.
  transformOrigin: Item.Center
  scale: mouse.pressed ? 0.98 : 1.0
  Behavior on scale { NumberAnimation { duration: 90; easing.type: Easing.OutCubic } }

  // Accent neon bloom on the selected chip.
  layer.enabled: Style.fx.glow > 0 && selected
  layer.effect: MultiEffect {
    shadowEnabled: true
    shadowColor: Style.fx.glowColor
    shadowBlur: 1.0
    shadowVerticalOffset: 0
    shadowHorizontalOffset: 0
    blurMax: Style.fx.glowRadius
    autoPaddingEnabled: true
  }

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

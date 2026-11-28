import QtQuick
import qs.Commons

// A row of a panel's live list (Wi-Fi networks, Bluetooth devices): a caption glyph, a name the network or device
// picked (never markup), a trailing status. The selected one (connected, active) is marked like an on PanelRow: its
// fill and a bar on the left edge; its glyph glows.
// Children go into a row at the right edge (a forget button), the status left of them; a right click is
// secondaryActivated.
Rectangle {
  id: root

  default property alias controls: controlRow.data
  property string glyph: ""
  property string label: ""
  property string trailing: ""
  property bool selected: false
  property bool failed: false
  // a control over the row is under the pointer: the row stays lit beneath it
  property bool controlHovered: false
  readonly property bool hovered: mouse.containsMouse || controlHovered
  readonly property bool highlighted: selected || activeFocus || hovered
  readonly property color _text: selected ? Colors.menu.selectedText : Colors.menu.text

  signal activated()
  signal secondaryActivated()

  height: Style.row.list
  radius: Style.shape.data
  color: mouse.pressed ? Style.pressedFill
    : selected ? Colors.menu.selectedBackground
    : activeFocus ? Style.focusFill
    : hovered ? Style.hoverFill : "transparent"

  Behavior on color { ColorAnimation { duration: Style.motion.fast; easing.type: Style.motion.fastEasing } }

  activeFocusOnTab: true
  Keys.onReturnPressed: root.activated()
  Keys.onEnterPressed: root.activated()
  Keys.onSpacePressed: root.activated()

  Rectangle {
    visible: root.selected
    width: Style.selectedBorderWidth
    height: parent.height
    color: Style.selectedMarkColor(Colors.menu.text, Colors.accent)
  }

  Label {
    id: glyphLabel
    anchors.left: parent.left
    anchors.leftMargin: Style.spacing.sm
    anchors.verticalCenter: parent.verticalCenter
    text: root.glyph
    color: root._text
    caption: true
    icon: true
    layer.enabled: Style.fx.glow > 0 && root.selected
    layer.effect: Glow {}
  }
  Label {
    anchors.left: glyphLabel.right
    anchors.leftMargin: Style.spacing.xs
    anchors.right: trailingLabel.left
    anchors.rightMargin: Style.spacing.xs
    anchors.verticalCenter: parent.verticalCenter
    text: root.label
    color: root._text
    elide: Text.ElideRight
  }
  Label {
    id: trailingLabel
    anchors.right: controlRow.left
    anchors.rightMargin: Style.spacing.sm
    anchors.verticalCenter: parent.verticalCenter
    text: root.trailing
    color: root.failed ? Colors.urgentText : root.highlighted ? Colors.foreground : Colors.textDim
    caption: true
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: true
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    cursorShape: Qt.PointingHandCursor
    onClicked: function(click) { if (click.button === Qt.RightButton) root.secondaryActivated(); else root.activated() }
  }

  // over the row's mouse area, so a control's click is its own
  Row {
    id: controlRow
    anchors.right: parent.right
    anchors.rightMargin: width > 0 ? Style.spacing.xs : 0
    anchors.verticalCenter: parent.verticalCenter
  }
}

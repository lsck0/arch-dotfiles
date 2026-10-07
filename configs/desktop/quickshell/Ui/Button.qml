import QtQuick
import qs.Commons

BorderSurface {
  id: root

  property string text: ""
  property string iconText: ""
  property string tooltipText: ""

  property bool selected: false
  property bool active: false
  property bool hasCursor: false
  property bool focusable: false
  property bool bordered: false

  property color foreground: Color.foreground
  property color background: "transparent"
  property color accent: Color.accent

  property string fontFamily: Style.font.family
  property real fontSize: Style.font.body
  property real iconSize: Style.font.icon
  property real horizontalPadding: Style.spacing.controlPaddingX
  property real verticalPadding: Style.spacing.controlPaddingY

  leftPadding: horizontalPadding
  rightPadding: horizontalPadding
  topPadding: verticalPadding
  bottomPadding: verticalPadding

  signal clicked()
  signal rightClicked()

  activeFocusOnTab: focusable
  Keys.onReturnPressed: if (focusable) root.clicked()
  Keys.onEnterPressed: if (focusable) root.clicked()
  Keys.onSpacePressed: if (focusable) root.clicked()

  // reserve the widest border any state can paint
  implicitWidth: row.implicitWidth + (horizontalPadding + _reservedBorder) * 2
  implicitHeight: row.implicitHeight + (verticalPadding + _reservedBorder) * 2
  radius: Style.shape.data

  readonly property bool hot: mouseArea.containsMouse || hasCursor
  readonly property bool _showFocusRing: focusable && activeFocus
  readonly property color _selectedColor: Style.selectedStateColor(root.foreground, root.accent)
  readonly property var _focusBorderSpec: Border.controlSpec("focus", root.foreground, root.accent)
  readonly property var _hoverBorderSpec: Border.controlSpec("hover-cursor", root.foreground, root.accent)
  readonly property var _selectedBorderSpec: Border.controlSpec("selected", root.foreground, root.accent)
  readonly property var _normalBorderSpec: Border.controlSpec("normal", root.foreground, root.accent)
  readonly property real _reservedBorder: Math.max(
    focusable ? Border.width(_focusBorderSpec) : 0,
    Border.width(_hoverBorderSpec),
    Border.width(_selectedBorderSpec),
    bordered ? Border.width(_normalBorderSpec) : 0)
  readonly property var _borderSpec: _showFocusRing ? _focusBorderSpec
    : hot                      ? _hoverBorderSpec
    : selected                 ? (Style.selectedBorderWidth > 0 ? _selectedBorderSpec : (bordered ? _normalBorderSpec : Border.none()))
    : bordered                 ? _normalBorderSpec
    : Border.none()

  color: mouseArea.pressed ? Style.pressedFillFor(root.foreground, root.accent)
    : _showFocusRing       ? Style.focusFillFor(root.foreground, root.accent)
    : hot                  ? Style.hoverFillFor(root.foreground, root.accent)
    : selected             ? Style.selectedFillFor(root.foreground, root.accent)
    : active               ? Style.selectedFillFor(root.foreground, root.accent)
    : background

  borderSpec: _borderSpec

  Behavior on color { ColorAnimation { duration: Style.motion.fast; easing.type: Style.motion.fastEasing } }

  transformOrigin: Item.Center
  scale: mouseArea.pressed ? 0.98 : 1.0
  Behavior on scale { NumberAnimation { duration: Style.motion.fast; easing.type: Style.motion.fastEasing } }

  readonly property bool _glowing: Style.fx.glow > 0 && (_showFocusRing || selected || active || mouseArea.pressed)
  layer.enabled: _glowing
  layer.effect: Glow {}

  PanelToolTip {
    visible: root.tooltipText !== "" && mouseArea.containsMouse
    text: root.tooltipText
    fontFamily: root.fontFamily
  }

  Row {
    id: row
    anchors.verticalCenter: parent.verticalCenter
    anchors.horizontalCenter: parent.horizontalCenter
    spacing: Style.spacing.controlGap

    Text {
      textFormat: Text.PlainText
      visible: root.iconText !== ""
      text: root.iconText
      color: root.selected ? root._selectedColor : root.foreground
      font.family: root.fontFamily
      font.pixelSize: root.iconSize
      anchors.verticalCenter: parent.verticalCenter
    }

    Text {
      textFormat: Text.PlainText
      visible: root.text !== ""
      text: root.text
      color: root.selected ? root._selectedColor : root.foreground
      font.family: root.fontFamily
      font.pixelSize: root.fontSize
      font.bold: root.selected
      anchors.verticalCenter: parent.verticalCenter
    }
  }

  MouseArea {
    id: mouseArea
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    onClicked: function(mouse) {
      if (root.focusable) root.forceActiveFocus()
      if (mouse.button === Qt.RightButton) root.rightClicked()
      else root.clicked()
    }
  }
}

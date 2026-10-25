pragma ComponentBehavior: Bound
import QtQuick
import qs.Commons

// One clickable control in four looks:
//   plain   an icon and/or text on a fill that lights on hover, focus, selection
//   icon    a square glyph button (panel toolbars, media transport)
//   action  a tinted "[ LABEL ]" verb (notification actions, dialogs)
//   chip    a selectable choice in a row of options
BorderSurface {
  id: root

  property string variant: "plain"

  property string text: ""
  property string iconText: ""
  property string tooltipText: ""

  property bool selected: false
  property bool active: false
  property bool danger: false
  property bool hasCursor: false
  property bool focusable: false
  property bool focused: activeFocus
  property bool bordered: false

  property color foreground: variant === "action" || variant === "chip" ? Colors.menu.text : Colors.foreground
  property color background: "transparent"
  property color accent: variant === "icon" ? foreground : Colors.accent

  property string fontFamily: variant === "icon" ? Style.font.iconFamily : Style.font.family
  property real fontSize: variant === "icon" ? Style.font.icon
    : variant === "plain" ? Style.font.body
    : Style.font.caption
  property real iconSize: variant === "action" ? Style.font.caption : Style.font.icon
  property real size: Math.max(Style.space(22), fontSize + Style.spacing.xs * 2)
  property real minimumWidth: variant === "chip" ? Style.space(40) : 0
  property real horizontalPadding: variant === "plain" ? Style.spacing.controlPaddingX
    : variant === "action" ? Style.spacing.md
    : variant === "chip" ? Style.spacing.sm
    : 0
  property real verticalPadding: variant === "plain" ? Style.spacing.controlPaddingY : 0

  signal clicked()
  signal rightClicked()

  readonly property bool isIcon: variant === "icon"
  readonly property bool isAction: variant === "action"
  readonly property bool isChip: variant === "chip"
  readonly property bool hot: (mouseArea.containsMouse || hasCursor) && enabled
  readonly property bool _showFocusRing: (focusable || isAction) && activeFocus

  activeFocusOnTab: focusable
  Keys.onReturnPressed: if (focusable) root.clicked()
  Keys.onEnterPressed: if (focusable) root.clicked()
  Keys.onSpacePressed: if (focusable) root.clicked()

  leftPadding: horizontalPadding
  rightPadding: horizontalPadding
  topPadding: verticalPadding
  bottomPadding: verticalPadding

  implicitWidth: isIcon ? size : Math.max(minimumWidth, row.implicitWidth + (horizontalPadding + _reservedBorder) * 2)
  implicitHeight: isIcon ? size
    : isAction || isChip ? Style.row.control
    : row.implicitHeight + (verticalPadding + _reservedBorder) * 2
  radius: Style.shape.data
  opacity: enabled ? 1 : (isAction || isChip ? Style.emphasis.disabled : 1)

  readonly property var _focusBorderSpec: Border.controlSpec("focus", root.foreground, root.accent)
  readonly property var _hoverBorderSpec: Border.controlSpec("hover-cursor", root.foreground, root.accent)
  readonly property var _selectedBorderSpec: Border.controlSpec("selected", root.foreground, root.accent)
  readonly property var _normalBorderSpec: Border.controlSpec("normal", root.foreground, Colors.accent)
  readonly property real _reservedBorder: isPlain ? Math.max(
    focusable ? Border.width(_focusBorderSpec) : 0,
    Border.width(_hoverBorderSpec),
    Border.width(_selectedBorderSpec),
    bordered ? Border.width(_normalBorderSpec) : 0) : 0
  readonly property bool isPlain: variant === "plain"

  borderSpec: isAction ? (activeFocus ? Border.flat(Util.alpha(foreground, Style.focusBorderAlpha), Style.focusBorderWidth) : Border.none())
    : isChip ? (focused ? Border.flat(Util.alpha(Style.focusStateColor(Colors.foreground, Colors.accent), Style.focusBorderAlpha), Style.focusBorderWidth)
      : hot && !selected ? Border.flat(Style.hoverBorderColor, Style.hoverBorderWidth)
      : Border.none())
    : _showFocusRing ? _focusBorderSpec
    : hot && (isPlain || bordered) ? _hoverBorderSpec
    : selected && isPlain ? (Style.selectedBorderWidth > 0 ? _selectedBorderSpec : (bordered ? _normalBorderSpec : Border.none()))
    : bordered ? _normalBorderSpec
    : Border.none()

  color: isAction ? Util.alpha(foreground, (hot || activeFocus ? 0.20 : 0.10) + (danger ? 0.08 : 0))
    : isChip ? (danger ? Util.alpha(Colors.urgent, hot ? 0.40 : 0.28)
      : selected ? Colors.menu.selectedBackground
      : mouseArea.pressed ? Style.pressedFill
      : hot ? Style.hoverFill
      : Style.normalFill)
    : mouseArea.pressed && isPlain ? Style.pressedFillFor(foreground, accent)
    : _showFocusRing ? Style.focusFillFor(foreground, accent)
    : hot ? Style.hoverFillFor(foreground, accent)
    : (selected || active) && isPlain ? Style.selectedFillFor(foreground, accent)
    : background

  Behavior on color { ColorAnimation { duration: Style.motion.fast; easing.type: Style.motion.fastEasing } }

  transformOrigin: Item.Center
  scale: mouseArea.pressed && !isIcon ? 0.98 : 1.0
  Behavior on scale { NumberAnimation { duration: Style.motion.fast; easing.type: Style.motion.fastEasing } }

  layer.enabled: Style.fx.glow > 0 && (isPlain ? (_showFocusRing || selected || active || mouseArea.pressed) : isChip && selected)
  layer.effect: Glow {}

  readonly property color _textColor: !enabled && isIcon ? Util.alpha(foreground, Style.emphasis.faint)
    : isChip ? (danger ? Colors.urgent : selected ? Colors.menu.selectedText : foreground)
    : selected ? Style.selectedStateColor(foreground, accent)
    : foreground
  readonly property bool _textGlow: Style.fx.glow > 0 && enabled
    && (isIcon ? (_showFocusRing || hot) : isAction && hot)

  PanelToolTip {
    visible: root.tooltipText !== "" && mouseArea.containsMouse
    text: root.tooltipText
    fontFamily: root.fontFamily
  }

  Row {
    id: row
    anchors.centerIn: parent
    spacing: root.isAction ? Style.spacing.xs : Style.spacing.controlGap

    Text {
      textFormat: Text.PlainText
      visible: root.iconText !== ""
      anchors.verticalCenter: parent.verticalCenter
      text: root.iconText
      color: root._textColor
      font.family: root.isPlain ? root.fontFamily : Style.font.iconFamily
      font.pixelSize: root.isIcon ? root.fontSize : root.iconSize
      layer.enabled: root.isIcon && root._textGlow
      layer.effect: Glow {}
    }

    Text {
      textFormat: Text.PlainText
      visible: root.text !== ""
      anchors.verticalCenter: parent.verticalCenter
      width: root.isChip ? Math.min(implicitWidth, root.width - Style.spacing.xs * 2) : implicitWidth
      horizontalAlignment: Text.AlignHCenter
      elide: root.isChip ? Text.ElideRight : Text.ElideNone
      text: root.isAction ? "[ " + root.text + " ]" : root.text
      color: root._textColor
      font.family: root.fontFamily
      font.pixelSize: root.fontSize
      font.bold: root.selected && root.isPlain
      font.capitalization: root.isAction ? Font.AllUppercase : Font.MixedCase
      font.letterSpacing: root.isAction ? Style.labelTracking : 0
      layer.enabled: root.isAction && root._textGlow
      layer.effect: Glow { shadowColor: root.foreground }
    }
  }

  MouseArea {
    id: mouseArea
    anchors.fill: parent
    enabled: root.enabled
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    onClicked: function(mouse) {
      // a chip keeps the keyboard focus where it was, its ring only follows the keyboard
      if (root.focusable && !root.isChip) root.forceActiveFocus()
      if (mouse.button === Qt.RightButton) root.rightClicked()
      else root.clicked()
    }
  }
}

import QtQuick
import QtQuick.Effects
import qs.Commons

// The button.
BorderSurface {
  id: root

  property string text: ""
  property string iconText: ""
  property string tooltipText: ""

  // State flags (see comment above for paint priority).
  property bool selected: false
  property bool active: false
  property bool hasCursor: false
  property bool focusable: false
  property bool bordered: false

  // Colors. Defaults track the theme; per-instance overrides are honored.
  property color foreground: Color.foreground
  property color background: "transparent"
  property color accent: Color.accent

  // Sizing.
  property string fontFamily: Style.font.family
  property real fontSize: Style.font.body
  property real iconSize: Style.font.icon
  property real iconRotation: 0
  property bool iconSpinning: false
  property real horizontalPadding: Style.spacing.controlPaddingX
  property real verticalPadding: Style.spacing.controlPaddingY
  property bool leftAlign: false

  leftPadding: horizontalPadding
  rightPadding: horizontalPadding
  topPadding: verticalPadding
  bottomPadding: verticalPadding

  // Tooltip palette. Auto-rendered if tooltipText is set.
  property color tooltipBackground: Color.tooltip.background
  property color tooltipForeground: Color.tooltip.text
  property color tooltipBorder: Color.tooltip.border

  signal clicked()
  signal rightClicked()
  signal hovered(bool isHovered)

  activeFocusOnTab: focusable
  Keys.onReturnPressed: if (focusable) root.clicked()
  Keys.onEnterPressed: if (focusable) root.clicked()
  Keys.onSpacePressed: if (focusable) root.clicked()

  // Reserve the largest border any visual state can paint.
  implicitWidth: row.implicitWidth + horizontalPadding * 2 + _reservedBorderLeft + _reservedBorderRight
  implicitHeight: row.implicitHeight + verticalPadding * 2 + _reservedBorderTop + _reservedBorderBottom
  radius: Style.cornerRadius

  readonly property bool hot: mouseArea.containsMouse || hasCursor
  readonly property bool _showFocusRing: focusable && activeFocus
  readonly property color _selectedColor: Style.selectedStateColor(root.foreground, root.accent)
  readonly property var _focusBorderSpec: Border.controlSpec("focus", root.foreground, root.accent)
  readonly property var _hoverBorderSpec: Border.controlSpec("hover-cursor", root.foreground, root.accent)
  readonly property var _selectedBorderSpec: Border.controlSpec("selected", root.foreground, root.accent)
  readonly property var _normalBorderSpec: Border.controlSpec("normal", root.foreground, root.accent)
  readonly property real _reservedBorderTop: Math.max(
    focusable ? Border.top(_focusBorderSpec) : 0,
    Border.top(_hoverBorderSpec),
    Border.top(_selectedBorderSpec),
    bordered ? Border.top(_normalBorderSpec) : 0)
  readonly property real _reservedBorderRight: Math.max(
    focusable ? Border.right(_focusBorderSpec) : 0,
    Border.right(_hoverBorderSpec),
    Border.right(_selectedBorderSpec),
    bordered ? Border.right(_normalBorderSpec) : 0)
  readonly property real _reservedBorderBottom: Math.max(
    focusable ? Border.bottom(_focusBorderSpec) : 0,
    Border.bottom(_hoverBorderSpec),
    Border.bottom(_selectedBorderSpec),
    bordered ? Border.bottom(_normalBorderSpec) : 0)
  readonly property real _reservedBorderLeft: Math.max(
    focusable ? Border.left(_focusBorderSpec) : 0,
    Border.left(_hoverBorderSpec),
    Border.left(_selectedBorderSpec),
    bordered ? Border.left(_normalBorderSpec) : 0)
  readonly property real _reservedContentLeftInset: _reservedBorderLeft + leftPadding
  // Style.selectedBorderWidth is 0 by default in this repo (no dedicated selected-state border token), so this matches upstream's Border.controlHasWidth("selected") for the no-override case exactly.
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

  // Border follows the same state precedence as fill.
  borderSpec: _borderSpec

  Behavior on color { ColorAnimation { duration: 120 } }

  // Subtle tactile press; fires only on the pressed state change.
  transformOrigin: Item.Center
  scale: mouseArea.pressed ? 0.98 : 1.0
  Behavior on scale { NumberAnimation { duration: 90; easing.type: Easing.OutCubic } }

  // Accent neon bloom on the focused/selected/active/pressed states.
  readonly property bool _glowing: Style.fx.glow > 0 && (_showFocusRing || selected || active || mouseArea.pressed)
  layer.enabled: _glowing
  layer.effect: MultiEffect {
    shadowEnabled: true
    shadowColor: Style.fx.glowColor
    shadowBlur: 1.0
    shadowVerticalOffset: 0
    shadowHorizontalOffset: 0
    blurMax: Style.fx.glowRadius
    autoPaddingEnabled: true
  }

  // Shared tooltip chrome so every button matches PanelToolTip (prompt tag, corner radius).
  PanelToolTip {
    visible: root.tooltipText !== "" && mouseArea.containsMouse
    text: root.tooltipText
    fontFamily: root.fontFamily
    panelForeground: root.tooltipForeground
    panelBackground: root.tooltipBackground
    panelBorder: root.tooltipBorder
  }

  Row {
    id: row
    anchors.verticalCenter: parent.verticalCenter
    anchors.left: root.leftAlign ? parent.left : undefined
    anchors.leftMargin: root.leftAlign ? root._reservedContentLeftInset : 0
    anchors.horizontalCenter: root.leftAlign ? undefined : parent.horizontalCenter
    spacing: Style.spacing.controlGap

    Text {
      textFormat: Text.PlainText
      visible: root.iconText !== ""
      text: root.iconText
      color: root.selected ? root._selectedColor : root.foreground
      font.family: root.fontFamily
      font.pixelSize: root.iconSize
      rotation: root.iconSpinning ? 0 : root.iconRotation
      transformOrigin: Item.Center
      anchors.verticalCenter: parent.verticalCenter

      RotationAnimation on rotation {
        from: 0
        to: 360
        duration: 900
        loops: Animation.Infinite
        running: root.iconSpinning
      }
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

  HoverHandler {
    onHoveredChanged: root.hovered(hovered)
  }
}

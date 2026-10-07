import QtQuick
import qs.Commons

// icon button for inline row actions
BorderSurface {
  id: root

  property string iconText: ""
  property string tooltipText: ""
  property color foreground: Color.foreground
  property color hoverColor: foreground
  property string fontFamily: Style.font.iconFamily
  property real fontSize: Style.font.icon
  property real size: Math.max(Style.space(22), fontSize + Style.spacing.xs * 2)

  property bool focusable: false
  property bool hasCursor: false
  property bool bordered: false

  signal clicked()
  signal hovered(bool isHovered)

  activeFocusOnTab: focusable
  Keys.onReturnPressed: if (focusable) root.clicked()
  Keys.onEnterPressed: if (focusable) root.clicked()
  Keys.onSpacePressed: if (focusable) root.clicked()

  implicitWidth: size
  implicitHeight: size
  radius: Style.shape.data

  readonly property bool _showFocusRing: focusable && activeFocus
  readonly property bool _hot: (mouse.containsMouse || root.hasCursor) && root.enabled
  readonly property var _borderSpec: _showFocusRing
    ? Border.controlSpec("focus", hoverColor, hoverColor)
    : (_hot && bordered
      ? Border.controlSpec("hover-cursor", hoverColor, hoverColor)
      : (bordered ? Border.controlSpec("normal", foreground, Color.accent) : Border.none()))

  color: _showFocusRing
    ? Style.focusFillFor(hoverColor, hoverColor)
    : (_hot
      ? Style.hoverFillFor(hoverColor, hoverColor)
      : "transparent")
  borderSpec: _borderSpec

  Behavior on color { ColorAnimation { duration: Style.motion.fast; easing.type: Style.motion.fastEasing } }

  Text {
    textFormat: Text.PlainText
    anchors.centerIn: parent
    text: root.iconText
    color: root.enabled
      ? (root._hot ? root.hoverColor : root.foreground)
      : Qt.darker(root.foreground, 2.0)
    font.family: root.fontFamily
    font.pixelSize: root.fontSize

    layer.enabled: Style.fx.glow > 0 && root.enabled && (root._showFocusRing || root._hot)
    layer.effect: Glow {}
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: root.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
    enabled: root.enabled
    onContainsMouseChanged: root.hovered(containsMouse)
    onClicked: {
      if (root.focusable) root.forceActiveFocus()
      root.clicked()
    }
  }

  PanelToolTip {
    visible: root.tooltipText !== "" && mouse.containsMouse
    text: root.tooltipText
    fontFamily: root.fontFamily
  }
}

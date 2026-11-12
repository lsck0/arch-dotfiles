import QtQuick
import qs.Commons

Item {
  id: root

  property var bar: null
  property string text: ""
  property string fontFamily: Style.font.family
  property real fontSize: Style.font.body
  property color foreground: Colors.bar.text
  property color activeColor: Colors.bar.active
  property bool active: false
  property real horizontalMargin: 8.5
  property real fixedWidth: -1
  property bool keepSpace: false
  property bool dimmed: false
  property bool concealed: false
  property bool interactive: true
  property bool useActiveColor: true
  property bool labelVisible: true
  // tints the button while hovered or pressed; off where the parent BarWidget already tints on hover
  property bool hoverFill: false
  property bool hasVisualContent: text !== ""
  property string tooltipText: ""

  signal pressed(int button)
  signal wheelMoved(int delta)
  signal entered()
  signal exited()

  function triggerPress(button) {
    if (root.bar) root.bar.hideTooltip(root)
    root.pressed(button)
  }

  function hideOwnTooltip() {
    if (root.bar) root.bar.hideTooltip(root)
  }

  onVisibleChanged: if (!visible) hideOwnTooltip()
  onInteractiveChanged: if (!interactive) hideOwnTooltip()
  onConcealedChanged: if (concealed) hideOwnTooltip()

  readonly property real scaledHorizontalMargin: Style.spaceReal(horizontalMargin)

  visible: hasVisualContent || keepSpace
  opacity: !hasVisualContent || concealed ? 0 : (dimmed ? 0.45 : 1)
  implicitWidth: fixedWidth > 0 ? fixedWidth : Math.max(12, label.implicitWidth + scaledHorizontalMargin * 2)
  implicitHeight: Style.bar.sizeHorizontal

  Behavior on opacity {
    NumberAnimation { duration: Style.motion.base; easing.type: Easing.BezierSpline; easing.bezierCurve: Style.motion.enter }
  }

  Rectangle {
    anchors.fill: parent
    z: -1
    visible: root.hoverFill && root.interactive
    radius: Style.shape.data
    color: mouseArea.pressed ? Style.pressedFill : mouseArea.containsMouse ? Style.hoverFill : "transparent"
    Behavior on color { ColorAnimation { duration: Style.motion.fast; easing.type: Style.motion.fastEasing } }
  }

  Label {
    id: label
    visible: root.labelVisible
    anchors.centerIn: parent
    text: root.text
    color: root.active && root.useActiveColor ? root.activeColor : root.foreground
    font.family: root.fontFamily
    font.pixelSize: root.fontSize
    renderType: Text.NativeRendering
    horizontalAlignment: Text.AlignHCenter
    verticalAlignment: Text.AlignVCenter

    layer.enabled: Style.fx.glow > 0 && root.active && root.useActiveColor
    layer.effect: Glow {}

    Behavior on color {
      ColorAnimation { duration: Style.motion.base; easing.type: Easing.BezierSpline; easing.bezierCurve: Style.motion.enter }
    }
  }

  MouseArea {
    id: mouseArea
    anchors.fill: parent
    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
    enabled: root.interactive
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onEntered: { if (root.bar) root.bar.showTooltip(root, root.tooltipText); root.entered() }
    onExited: { if (root.bar) root.bar.hideTooltip(root); root.exited() }
    onClicked: function(mouse) { root.triggerPress(mouse.button) }
    onWheel: function(wheel) { root.wheelMoved(wheel.angleDelta.y) }
  }
}

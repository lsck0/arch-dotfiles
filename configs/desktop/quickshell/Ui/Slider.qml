import QtQuick
import qs.Commons

Item {
  id: root

  property real value: 0
  property real minimum: 0
  property real maximum: 1
  property real step: 0.05
  property bool integer: false
  // the unfilled track is a control edge like a field's border: 3:1 on the background
  property color trackColor: Style.normalBorderColor
  property color fillColor: Colors.foreground
  property color knobColor: Colors.foreground
  property bool dragging: false
  property real trackHeight: Style.spacing.xxs
  property real knobSize: Style.spacing.lg
  property real knobWidth: Style.spacing.xxs
  property real liveValue: value

  onValueChanged: if (!dragging) liveValue = value

  signal moved(real value)
  signal released(real value)

  signal rightClicked()

  readonly property real coarseScale: 4
  readonly property real fineScale: 0.2

  activeFocusOnTab: true
  function setTo(value) {
    var next = Math.max(root.minimum, Math.min(root.maximum, value))
    if (root.integer) next = Math.round(next)
    root.liveValue = next
    root.moved(next)
    root.released(next)
  }
  function nudge(direction, scale) {
    var step = root.step * (scale === undefined ? 1 : scale)
    root.setTo(root.liveValue + direction * (root.integer ? Math.max(1, Math.round(step)) : step))
  }
  Keys.onPressed: function(event) {
    var scale = event.modifiers & Qt.ShiftModifier ? root.coarseScale : event.modifiers & Qt.ControlModifier ? root.fineScale : 1
    if (event.key === Qt.Key_Left || event.key === Qt.Key_H) root.nudge(-1, scale)
    else if (event.key === Qt.Key_Right || event.key === Qt.Key_L) root.nudge(1, scale)
    else if (event.key === Qt.Key_PageDown) root.nudge(-1, root.coarseScale)
    else if (event.key === Qt.Key_PageUp) root.nudge(1, root.coarseScale)
    else if (event.key === Qt.Key_Home) root.setTo(root.minimum)
    else if (event.key === Qt.Key_End) root.setTo(root.maximum)
    else return
    event.accepted = true
  }

  implicitWidth: Style.space(200)
  implicitHeight: Math.max(Style.space(22), knobSize + Style.spacing.sm)

  readonly property real range: Math.max(0.0001, maximum - minimum)
  readonly property real progress: Math.max(0, Math.min(1, (liveValue - minimum) / range))
  readonly property bool _hot: mouseArea.containsMouse || root.dragging || root.activeFocus

  Rectangle {
    anchors.fill: parent
    anchors.leftMargin: -Style.spacing.xs
    anchors.rightMargin: -Style.spacing.xs
    radius: Style.shape.data
    color: root.activeFocus ? Style.focusFill : "transparent"
    Behavior on color { ColorAnimation { duration: Style.motion.fast; easing.type: Style.motion.fastEasing } }
  }

  Rectangle {
    id: track
    anchors.verticalCenter: parent.verticalCenter
    anchors.left: parent.left
    anchors.right: parent.right
    height: root.trackHeight
    radius: Style.shape.data
    color: root.trackColor
  }

  Rectangle {
    id: fill
    anchors.verticalCenter: track.verticalCenter
    anchors.left: track.left
    height: track.height
    radius: Style.shape.data
    color: root.fillColor
    width: track.width * root.progress

    Behavior on width {
      enabled: !root.dragging
      NumberAnimation { duration: Style.motion.base; easing.type: Easing.BezierSpline; easing.bezierCurve: Style.motion.enter }
    }
  }

  Rectangle {
    width: root.knobWidth
    height: root._hot ? root.knobSize : Math.round(root.knobSize * 0.75)
    radius: Style.shape.data
    color: root.knobColor
    anchors.verticalCenter: track.verticalCenter
    x: Math.max(0, Math.min(track.width - width, track.width * root.progress - width / 2))

    layer.enabled: Style.fx.glow > 0 && root._hot
    layer.effect: Glow {}

    Behavior on x {
      enabled: !root.dragging
      NumberAnimation { duration: Style.motion.base; easing.type: Easing.BezierSpline; easing.bezierCurve: Style.motion.enter }
    }
    Behavior on height {
      NumberAnimation { duration: Style.motion.fast; easing.type: Style.motion.fastEasing }
    }
  }

  MouseArea {
    id: mouseArea
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    acceptedButtons: Qt.LeftButton | Qt.RightButton

    function valueFromX(x) {
      var clamped = Math.max(0, Math.min(track.width, x))
      var raw = root.minimum + (clamped / track.width) * root.range
      if (root.integer) raw = Math.round(raw)
      return Math.max(root.minimum, Math.min(root.maximum, raw))
    }

    onPressed: function(mouse) {
      if (mouse.button !== Qt.LeftButton) return
      root.dragging = true
      var next = valueFromX(mouse.x)
      root.liveValue = next
      root.moved(next)
    }
    onClicked: function(mouse) {
      if (mouse.button === Qt.RightButton) root.rightClicked()
    }
    onPositionChanged: function(mouse) {
      if (!root.dragging) return
      var next = valueFromX(mouse.x)
      root.liveValue = next
      root.moved(next)
    }
    onReleased: function(mouse) {
      if (mouse.button !== Qt.LeftButton) return
      var target = root.liveValue
      root.dragging = false
      root.released(target)
    }
    onWheel: function(wheel) {
      if (wheel.angleDelta.y === 0) return
      root.nudge(wheel.angleDelta.y > 0 ? 1 : -1)
    }
  }
}

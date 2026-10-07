import QtQuick
import qs.Commons

// square slider: hairline track, 2px bar knob, wheel and drag
Item {
  id: root

  property QtObject bar: null
  property real value: 0
  property real minimum: 0
  property real maximum: 1
  property real step: 0.05
  property bool integer: false
  // Bar exposes barForeground, not foreground
  property color trackColor: bar ? Style.selectedFillFor(bar.barForeground, Color.accent) : Style.selectedFill
  property color fillColor: bar ? bar.barForeground : Color.foreground
  property color knobColor: bar ? bar.barForeground : Color.foreground
  property bool dragging: false
  property real trackHeight: Style.spacing.xxs
  property real knobSize: Style.spacing.lg
  property real knobWidth: Style.spacing.xxs
  property real liveValue: value

  onValueChanged: if (!dragging) liveValue = value

  signal moved(real value)
  signal released(real value)

  signal rightClicked()

  // Left / Right (h / l) step it; Up / Down stay with the drawer's focus walk
  activeFocusOnTab: true
  function nudge(direction) {
    var next = Math.max(root.minimum, Math.min(root.maximum, root.liveValue + direction * root.step))
    if (root.integer) next = Math.round(next)
    root.liveValue = next
    root.moved(next)
    root.released(next)
  }
  Keys.onPressed: function(event) {
    if (event.key === Qt.Key_Left || event.text === "h") root.nudge(-1)
    else if (event.key === Qt.Key_Right || event.text === "l") root.nudge(1)
    else return
    event.accepted = true
  }

  implicitWidth: Style.space(200)
  implicitHeight: Math.max(Style.space(22), knobSize + Style.spacing.sm)

  readonly property real range: Math.max(0.0001, maximum - minimum)
  readonly property real progress: Math.max(0, Math.min(1, (liveValue - minimum) / range))
  readonly property bool _hot: mouseArea.containsMouse || root.dragging || root.activeFocus

  // data shape: hairline track, filled run, the knob a 2px vertical bar
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
    id: knob
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
      // capture first, clearing dragging resets liveValue
      var target = root.liveValue
      root.dragging = false
      root.released(target)
      root.liveValue = root.value
    }
    onWheel: function(wheel) { root.nudge(wheel.angleDelta.y > 0 ? 1 : -1) }
  }
}

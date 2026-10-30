pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import qs.Commons

Item {
  id: root

  property var values: []
  property real minValue: 0
  property real maxValue: 0
  property color color: Colors.accent
  property real lineWidth: 1.6
  property real fillAlpha: 0.22
  property bool glow: false
  readonly property real dotLift: 0.35

  implicitWidth: Style.space(64)
  implicitHeight: Style.space(18)

  onValuesChanged: {
    cv.requestPaint()
    if (pulsing && onScreen && Style.motion.enabled) ping.restart()
  }
  onWidthChanged: cv.requestPaint()
  onHeightChanged: cv.requestPaint()
  onColorChanged: cv.requestPaint()

  readonly property bool onScreen: visible && (QsWindow.window ? QsWindow.window.visible : true) // qmllint disable missing-property

  property bool pulsing: true
  property real pulse: 0
  SequentialAnimation {
    id: ping
    NumberAnimation { target: root; property: "pulse"; to: 1; duration: Style.motion.ambient / 2; easing.type: Style.motion.ambientEasing }
    NumberAnimation { target: root; property: "pulse"; to: 0; duration: Style.motion.ambient / 2; easing.type: Style.motion.ambientEasing }
  }

  // auto-range padding fraction when minValue/maxValue are not set
  readonly property real autoRangePad: 0.15
  readonly property var valueRange: {
    var v = root.values || []
    var n = v.length
    var mn = root.minValue, mx = root.maxValue
    if (mx <= mn) {
      mn = Infinity; mx = -Infinity
      for (let i = 0; i < n; i++) { mn = Math.min(mn, v[i]); mx = Math.max(mx, v[i]) }
      let pad = (mx - mn) * root.autoRangePad
      if (!(pad > 0)) pad = 1
      mn -= pad; mx += pad
    }
    return { mn: mn, mx: mx }
  }

  readonly property point lastPoint: {
    var v = root.values || []
    var n = v.length
    var w = width, h = height
    if (n < 1) return Qt.point(w, h)
    var mn = root.valueRange.mn, mx = root.valueRange.mx
    var ly = h - ((v[n - 1] - mn) / (mx - mn)) * h
    return Qt.point(w, ly)
  }

  Canvas {
    id: cv
    anchors.fill: parent

    property var gradCache: null
    property real gradH: -1
    property string gradKey: ""

    onPaint: {
      var ctx = getContext("2d")
      ctx.reset()
      var v = root.values || []
      var n = v.length
      var w = width, h = height
      var c = root.color

      ctx.strokeStyle = Util.alpha(c, 0.10)
      ctx.lineWidth = 1
      for (let g = 1; g <= 3; g++) {
        let gy = Math.round(h * g / 4) + 0.5
        ctx.beginPath(); ctx.moveTo(0, gy); ctx.lineTo(w, gy); ctx.stroke()
      }
      if (n < 1) return

      var mn = root.valueRange.mn, mx = root.valueRange.mx
      var stepX = n > 1 ? w / (n - 1) : 0
      function px(i) { return n > 1 ? i * stepX : w }
      function py(val) { return h - ((val - mn) / (mx - mn)) * h }

      var key = c.toString() + "|" + root.fillAlpha
      if (!cv.gradCache || cv.gradH !== h || cv.gradKey !== key) {
        let grad = ctx.createLinearGradient(0, 0, 0, h)
        grad.addColorStop(0, Util.alpha(c, root.fillAlpha))
        grad.addColorStop(1, Util.alpha(c, 0))
        cv.gradCache = grad; cv.gradH = h; cv.gradKey = key
      }
      ctx.beginPath()
      ctx.moveTo(px(0), py(v[0]))
      for (let j = 1; j < n; j++) ctx.lineTo(px(j), py(v[j]))
      ctx.lineTo(w, h); ctx.lineTo(0, h); ctx.closePath()
      ctx.fillStyle = cv.gradCache; ctx.fill()

      ctx.beginPath()
      ctx.moveTo(px(0), py(v[0]))
      for (let k = 1; k < n; k++) ctx.lineTo(px(k), py(v[k]))
      ctx.strokeStyle = c; ctx.lineWidth = root.lineWidth; ctx.stroke()
    }
  }

  Rectangle {
    visible: (root.values || []).length > 0
    width: Style.space(5); height: Style.space(5); radius: Style.shape.data
    color: root.color
    x: root.lastPoint.x - width / 2
    y: root.lastPoint.y - height / 2
    scale: 1 + root.pulse * 1.2
    opacity: 0.18 + root.pulse * 0.12
  }
  Rectangle {
    visible: (root.values || []).length > 0
    width: Style.space(4); height: Style.space(4); radius: Style.shape.data
    // toward the foreground, so the dot stands out on light themes too (Qt.lighter washes it out there)
    color: Qt.tint(root.color, Util.alpha(Colors.foreground, root.dotLift))
    x: root.lastPoint.x - width / 2
    y: root.lastPoint.y - height / 2
  }

  layer.enabled: root.glow && Style.fx.glow > 0
  layer.effect: Glow {
    shadowColor: root.color
    shadowBlur: 0.7
  }
}

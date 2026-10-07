import QtQuick
import Quickshell
import qs.Commons

// values newest last
Item {
  id: root

  property var values: []
  property real minValue: 0
  // <= minValue auto-scales to the data
  property real maxValue: 0
  property color color: Color.accent
  property real lineWidth: 1.6
  property real fillAlpha: 0.22
  // opt-in: only for series that change rarely, a live one would re-render the effect per sample
  property bool glow: false

  implicitWidth: 64
  implicitHeight: 18

  onValuesChanged: {
    cv.requestPaint()
    if (pulsing && onScreen && Style.motion.enabled) ping.restart()
  }
  onWidthChanged: cv.requestPaint()
  onHeightChanged: cv.requestPaint()
  onColorChanged: cv.requestPaint()

  // items keep visible: true inside a hidden window, endless animations would tick unseen
  readonly property bool onScreen: visible && (QsWindow.window ? QsWindow.window.visible : true)

  // always-visible hosts (the bar) turn this off; one ping per new sample, never a loop
  property bool pulsing: true
  // drives the overlay dots so the ping never repaints the canvas
  property real pulse: 0
  SequentialAnimation {
    id: ping
    NumberAnimation { target: root; property: "pulse"; to: 1; duration: Style.motion.ambient / 2; easing.type: Style.motion.ambientEasing }
    NumberAnimation { target: root; property: "pulse"; to: 0; duration: Style.motion.ambient / 2; easing.type: Style.motion.ambientEasing }
  }

  // mirrors the canvas mapping for the newest sample
  readonly property point lastPoint: {
    var v = root.values || []
    var n = v.length
    var w = width, h = height
    if (n < 1) return Qt.point(w, h)
    var mn = root.minValue, mx = root.maxValue
    if (mx <= mn) {
      mn = Infinity; mx = -Infinity
      for (var i = 0; i < n; i++) { mn = Math.min(mn, v[i]); mx = Math.max(mx, v[i]) }
      var pad = (mx - mn) * 0.15
      if (!(pad > 0)) pad = 1
      mn -= pad; mx += pad
    }
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

      ctx.strokeStyle = Qt.rgba(c.r, c.g, c.b, 0.10)
      ctx.lineWidth = 1
      for (var g = 1; g <= 3; g++) {
        var gy = Math.round(h * g / 4) + 0.5
        ctx.beginPath(); ctx.moveTo(0, gy); ctx.lineTo(w, gy); ctx.stroke()
      }
      if (n < 1) return

      var mn = root.minValue, mx = root.maxValue
      if (mx <= mn) {
        mn = Infinity; mx = -Infinity
        for (var i = 0; i < n; i++) { mn = Math.min(mn, v[i]); mx = Math.max(mx, v[i]) }
        var pad = (mx - mn) * 0.15
        if (!(pad > 0)) pad = 1
        mn -= pad; mx += pad
      }
      var stepX = n > 1 ? w / (n - 1) : 0
      function px(i) { return n > 1 ? i * stepX : w }
      function py(val) { return h - ((val - mn) / (mx - mn)) * h }

      var key = c.toString() + "|" + root.fillAlpha
      if (!cv.gradCache || cv.gradH !== h || cv.gradKey !== key) {
        var grad = ctx.createLinearGradient(0, 0, 0, h)
        grad.addColorStop(0, Qt.rgba(c.r, c.g, c.b, root.fillAlpha))
        grad.addColorStop(1, Qt.rgba(c.r, c.g, c.b, 0))
        cv.gradCache = grad; cv.gradH = h; cv.gradKey = key
      }
      ctx.beginPath()
      ctx.moveTo(px(0), py(v[0]))
      for (var j = 1; j < n; j++) ctx.lineTo(px(j), py(v[j]))
      ctx.lineTo(w, h); ctx.lineTo(0, h); ctx.closePath()
      ctx.fillStyle = cv.gradCache; ctx.fill()

      ctx.beginPath()
      ctx.moveTo(px(0), py(v[0]))
      for (var k = 1; k < n; k++) ctx.lineTo(px(k), py(v[k]))
      ctx.strokeStyle = c; ctx.lineWidth = root.lineWidth; ctx.stroke()
    }
  }

  Rectangle {
    visible: (root.values || []).length > 0
    width: 5; height: 5; radius: Style.shape.data
    color: root.color
    x: root.lastPoint.x - width / 2
    y: root.lastPoint.y - height / 2
    scale: 1 + root.pulse * 1.2
    opacity: 0.18 + root.pulse * 0.12
  }
  Rectangle {
    visible: (root.values || []).length > 0
    width: 4; height: 4; radius: Style.shape.data
    color: Qt.lighter(root.color, 1.4)
    x: root.lastPoint.x - width / 2
    y: root.lastPoint.y - height / 2
  }

  layer.enabled: root.glow && Style.fx.glow > 0
  layer.effect: Glow {
    shadowColor: root.color
    shadowBlur: 0.7
  }
}

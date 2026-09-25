import QtQuick
import QtQuick.Effects
import qs.Commons

// Glowing telemetry graph: HUD gridlines, gradient area fill, curve, and a
// pulsing leading-edge dot. Values are a numeric array, newest last.
Item {
  id: root

  property var values: []
  property real minValue: 0
  property real maxValue: 0        // <= minValue auto-scales (both ends) to the data
  property color color: Color.accent
  property real lineWidth: 1.6
  property real fillAlpha: 0.22

  implicitWidth: 64
  implicitHeight: 18

  onValuesChanged: cv.requestPaint()
  onWidthChanged: cv.requestPaint()
  onHeightChanged: cv.requestPaint()
  onColorChanged: cv.requestPaint()

  // Pulsing leading dot: a phase the overlay dots bind to, so the pulse never repaints the Canvas.
  property real pulse: 0
  SequentialAnimation on pulse {
    running: root.visible
    loops: Animation.Infinite
    NumberAnimation { to: 1; duration: 900; easing.type: Easing.InOutSine }
    NumberAnimation { to: 0; duration: 900; easing.type: Easing.InOutSine }
  }

  // Pixel position of the newest sample, mirrored from the Canvas mapping so the overlay dot tracks it without a repaint. px(n-1) is always the right edge.
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

    // Area-fill gradient cached and rebuilt only when height/color/alpha change, not every paint.
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

      // HUD gridlines (faint), always drawn so an empty/flat graph still reads as a gauge.
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

      // area fill: accent, bright under the line fading to nothing at the base (gradient cached)
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

      // the curve
      ctx.beginPath()
      ctx.moveTo(px(0), py(v[0]))
      for (var k = 1; k < n; k++) ctx.lineTo(px(k), py(v[k]))
      ctx.strokeStyle = c; ctx.lineWidth = root.lineWidth; ctx.stroke()
    }
  }

  // Pulsing leading-edge dot, an overlay so its animation never triggers a Canvas repaint.
  Rectangle {
    id: haloDot
    visible: (root.values || []).length > 0
    width: 5; height: 5; radius: 2.5
    color: root.color
    x: root.lastPoint.x - width / 2
    y: root.lastPoint.y - height / 2
    scale: 1 + root.pulse * 1.2
    opacity: 0.18 + root.pulse * 0.12
  }
  Rectangle {
    id: coreDot
    visible: (root.values || []).length > 0
    width: 4; height: 4; radius: 2
    color: Qt.lighter(root.color, 1.4)
    x: root.lastPoint.x - width / 2
    y: root.lastPoint.y - height / 2
  }

  layer.enabled: Style.fx.glow > 0
  layer.effect: MultiEffect {
    shadowEnabled: true
    shadowColor: root.color
    shadowBlur: 0.7
    shadowVerticalOffset: 0
    shadowHorizontalOffset: 0
    blurMax: Style.fx.glowRadius
    autoPaddingEnabled: true
  }
}

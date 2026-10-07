import QtQuick
import qs.Commons

// repaints only on new rows or resize, so it scrolls one column per sample
Item {
  id: root

  // [{ values: [newest last], max }]
  property var rows: []
  property int cols: 60
  property bool active: true
  property real cellGap: 1

  implicitWidth: Style.space(200)
  implicitHeight: Style.space(72)

  onRowsChanged: if (active) cv.requestPaint()
  onActiveChanged: if (active) cv.requestPaint()
  onWidthChanged: cv.requestPaint()
  onHeightChanged: cv.requestPaint()

  // low values fade in as accent, high ones walk the severity ramp
  readonly property real fadeEnd: 0.5
  readonly property real alphaFloor: 0.05
  function colorFor(t) {
    var a = alphaFloor + (1 - alphaFloor) * Math.min(1, t / fadeEnd)
    return Util.alpha(Color.ramp(t), a)
  }

  Canvas {
    id: cv
    anchors.fill: parent
    // requestPaint is dropped until the canvas is available
    onAvailableChanged: if (available) requestPaint()
    Component.onCompleted: requestPaint()

    onPaint: {
      var ctx = getContext("2d")
      ctx.reset()
      var rws = root.rows || []
      var nr = rws.length
      if (nr === 0) return
      var w = width, h = height
      var rowH = h / nr
      var cellW = w / root.cols
      var g = root.cellGap

      for (var r = 0; r < nr; r++) {
        var row = rws[r] || {}
        var vals = row.values || []
        var mx = row.max || 100
        var n = vals.length
        var y0 = r * rowH
        for (var i = 0; i < n; i++) {
          var x = w - (n - i) * cellW
          if (x + cellW < 0) continue
          var t = Math.max(0, Math.min(1, mx > 0 ? vals[i] / mx : 0))
          ctx.fillStyle = root.colorFor(t)
          ctx.fillRect(x, y0 + g, cellW + 0.6, rowH - g * 2)
        }
      }
      ctx.strokeStyle = Util.alpha(Color.foreground, 0.10)
      ctx.lineWidth = 1
      for (var s = 1; s < nr; s++) {
        var sy = Math.round(s * rowH) + 0.5
        ctx.beginPath(); ctx.moveTo(0, sy); ctx.lineTo(w, sy); ctx.stroke()
      }
    }

    layer.enabled: Style.fx.glow > 0
    layer.effect: Glow { shadowBlur: 0.6 }
  }
}

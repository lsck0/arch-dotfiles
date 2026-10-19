import QtQuick
import qs.Commons

Item {
  id: root

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

  readonly property real fadeEnd: 0.5
  readonly property real alphaFloor: 0.05
  function colorFor(t) {
    var a = alphaFloor + (1 - alphaFloor) * Math.min(1, t / fadeEnd)
    return Util.alpha(Colors.ramp(t), a)
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

      for (let r = 0; r < nr; r++) {
        let row = rws[r] || {}
        let vals = row.values || []
        let mx = row.max || 100
        let n = vals.length
        let y0 = r * rowH
        for (let i = 0; i < n; i++) {
          let x = w - (n - i) * cellW
          if (x + cellW < 0) continue
          let t = Math.max(0, Math.min(1, mx > 0 ? vals[i] / mx : 0))
          ctx.fillStyle = root.colorFor(t)
          ctx.fillRect(x, y0 + g, cellW + 0.6, rowH - g * 2)
        }
      }
      ctx.strokeStyle = Util.alpha(Colors.foreground, 0.10)
      ctx.lineWidth = 1
      for (let s = 1; s < nr; s++) {
        let sy = Math.round(s * rowH) + 0.5
        ctx.beginPath(); ctx.moveTo(0, sy); ctx.lineTo(w, sy); ctx.stroke()
      }
    }

    layer.enabled: Style.fx.glow > 0
    layer.effect: Glow { shadowBlur: 0.6 }
  }
}

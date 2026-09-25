import QtQuick
import QtQuick.Effects
import qs.Commons

// Scrolling 2D waterfall / flux heatmap: one horizontal row of history per
// metric, newest sample flush right, intensity colour-mapped from a near-empty
// accent wash through accent to hot criticality (warn -> recording -> live).
// It scrolls exactly one column per data sample because it repaints only when
// `rows` changes (the ~5s tick) or on resize -- never on a clock. Paint is
// gated on `active` and glow on Style.fx.glow.
Item {
  id: root

  // [{ values: [numbers, newest last], max: Number }] -- one entry per metric row.
  property var rows: []
  // History capacity; column width is width / cols so columns stay stable as data streams in.
  property int cols: 60
  property bool active: true
  property real cellGap: 1

  implicitWidth: Style.space(200)
  implicitHeight: Style.space(72)

  onRowsChanged: if (active) cv.requestPaint()
  onActiveChanged: if (active) cv.requestPaint()
  onWidthChanged: cv.requestPaint()
  onHeightChanged: cv.requestPaint()

  // Five-stop plasma colour ramp shared by every cell.
  function _mix(a, b, t) {
    return Qt.rgba(a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t,
                   a.b + (b.b - a.b) * t, a.a + (b.a - a.a) * t)
  }
  function colorFor(t) {
    var s0 = Util.alpha(Color.accent, 0.05)
    var s1 = Util.alpha(Color.accent, 0.45)
    var s2 = Util.alpha(Color.accent, 0.95)
    var s3 = Util.alpha(Color.semantic.recording, 0.95)
    var s4 = Util.alpha(Color.semantic.live, 1.0)
    if (t <= 0) return s0
    if (t < 0.35) return _mix(s0, s1, t / 0.35)
    if (t < 0.6) return _mix(s1, s2, (t - 0.35) / 0.25)
    if (t < 0.82) return _mix(s2, s3, (t - 0.6) / 0.22)
    return _mix(s3, s4, Math.min(1, (t - 0.82) / 0.18))
  }

  Canvas {
    id: cv
    anchors.fill: parent
    // Canvas drops requestPaint before it is available; paint once it is ready.
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
      // Faint row separators.
      ctx.strokeStyle = Util.alpha(Color.foreground, 0.10)
      ctx.lineWidth = 1
      for (var s = 1; s < nr; s++) {
        var sy = Math.round(s * rowH) + 0.5
        ctx.beginPath(); ctx.moveTo(0, sy); ctx.lineTo(w, sy); ctx.stroke()
      }
    }

    layer.enabled: Style.fx.glow > 0
    layer.effect: MultiEffect {
      shadowEnabled: true
      shadowColor: Style.fx.glowColor
      shadowBlur: 0.6
      shadowVerticalOffset: 0
      shadowHorizontalOffset: 0
      blurMax: Style.fx.glowRadius
      autoPaddingEnabled: true
    }
  }
}

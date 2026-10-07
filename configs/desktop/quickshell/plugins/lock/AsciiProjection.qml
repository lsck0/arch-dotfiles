import QtQuick
import qs.Commons

/**
 * AsciiProjection: the lock's wallpaper re-drawn as text (signature C).
 *
 * On each lock the wallpaper is sampled once into a grid of at most maxCols x maxRows cells (one
 * drawImage + getImageData), luminance picks a glyph from ramp and the pixel, nudged toward the
 * accent, colours it. A rain then develops the picture: each column's drop leaves the projected
 * glyphs behind it, and everything has landed after developMs. At rest it is static, no timer
 * runs. ripple() sends one short drop through a few columns (keypresses).
 *
 * Properties:
 *   image    a decoded Image item of the wallpaper (Lock.qml's blurred one)
 *   active   the lock surface is up; going false drops the sample
 *   animate  rain and ripples; false draws the end state at once
 *
 * Usage:
 *   AsciiProjection { anchors.fill: parent; image: wallpaper; active: root.locked; animate: Style.motion.enabled }
 */
Item {
  id: root

  property Item image: null
  property bool active: false
  property bool animate: true

  readonly property string ramp: " .:-=+*#%@"
  readonly property int maxCols: 240
  readonly property int maxRows: 70
  // monospace advance over line height
  readonly property real glyphAspect: 0.6
  readonly property int developMs: 4000
  readonly property int frameMs: 40
  // how far each cell's colour moves toward the accent
  readonly property real paletteNudge: 0.3
  readonly property int rippleColumns: 5
  readonly property int rippleMs: 600

  readonly property real cellH: Math.max(height / maxRows, Style.font.caption)
  readonly property real cellW: Math.max(width / maxCols, cellH * glyphAspect)
  readonly property int cols: Math.max(1, Math.floor(width / cellW))
  readonly property int rows: Math.max(1, Math.floor(height / cellH))

  // sampled grid, row-major; null until the next paint samples it
  property var glyphs: null
  property var colors: null
  // per column: { y: head row, speed: rows per frame, drawn: last row drawn as head }
  property var heads: []
  property int frames: 0

  function project() {
    timer.stop()
    root.glyphs = null
    root.colors = null
    root.heads = []
    canvas.requestPaint()
  }

  function ripple() {
    if (!root.animate || !root.glyphs) return
    var centre = Math.floor(Math.random() * root.cols)
    var half = Math.floor(root.rippleColumns / 2)
    var speed = root.rows * root.frameMs / root.rippleMs
    var next = root.heads.slice()
    for (var c = Math.max(0, centre - half); c <= Math.min(root.cols - 1, centre + half); c++)
      next[c] = { y: 0, speed: speed, drawn: 0 }
    root.heads = next
    root.frames = 0
    timer.start()
  }

  onActiveChanged: {
    if (active) project()
    else {
      timer.stop()
      root.glyphs = null
      root.colors = null
    }
  }
  onColsChanged: if (active) project()
  onRowsChanged: if (active) project()

  Connections {
    target: root.image
    function onStatusChanged() { if (root.active) root.project() }
  }

  Canvas {
    id: canvas
    anchors.fill: parent

    function sample(ctx) {
      ctx.clearRect(0, 0, width, height)
      ctx.drawImage(root.image, 0, 0, root.cols, root.rows)
      var data = ctx.getImageData(0, 0, root.cols, root.rows).data
      ctx.clearRect(0, 0, root.cols, root.rows)
      var acc = Color.accent
      var k = root.paletteNudge
      var last = root.ramp.length - 1
      var g = [], col = []
      for (var i = 0; i < root.cols * root.rows; i++) {
        var r = data[i * 4] / 255, gr = data[i * 4 + 1] / 255, b = data[i * 4 + 2] / 255
        var lum = 0.2126 * r + 0.7152 * gr + 0.0722 * b
        g.push(root.ramp.charAt(Math.round(lum * last)))
        col.push(Qt.rgba(r + (acc.r - r) * k, gr + (acc.g - gr) * k, b + (acc.b - b) * k, 1))
      }
      root.glyphs = g
      root.colors = col
      var heads = []
      var developFrames = root.developMs / root.frameMs
      for (var c = 0; c < root.cols; c++) {
        // staggered starts, all columns land within developMs
        var start = Math.random() * root.rows * 0.5
        heads.push({ y: -start, speed: (root.rows + start) / developFrames * (1 + Math.random() * 0.5), drawn: 0 })
      }
      root.heads = heads
    }

    function cell(ctx, c, r, lead) {
      var x = c * root.cellW, y = r * root.cellH
      ctx.clearRect(x, y, root.cellW, root.cellH)
      var glyph = root.glyphs[r * root.cols + c]
      if (lead) {
        ctx.fillStyle = Color.accent
        glyph = glyph === " " ? "." : glyph
      } else {
        if (glyph === " ") return
        ctx.fillStyle = root.colors[r * root.cols + c]
      }
      ctx.fillText(glyph, x, y)
    }

    onPaint: {
      var ctx = getContext("2d")
      if (!root.glyphs) {
        // nothing to show yet, and nothing of the last lock either
        if (!root.active || !root.image || root.image.status !== Image.Ready) {
          ctx.clearRect(0, 0, width, height)
          return
        }
        sample(ctx)
        root.frames = 0
        if (root.animate) timer.start()
        else for (var h = 0; h < root.heads.length; h++) root.heads[h].y = root.rows
      }
      ctx.font = Math.floor(root.cellH) + "px '" + Style.font.family + "'"
      ctx.textBaseline = "top"
      for (var c = 0; c < root.heads.length; c++) {
        var head = root.heads[c]
        if (!head) continue
        var to = Math.min(Math.floor(head.y), root.rows)
        // the drop leaves the projection behind it
        for (var r = Math.max(0, head.drawn); r < to; r++) cell(ctx, c, r, false)
        if (to >= 0 && to < root.rows) cell(ctx, c, to, true)
        head.drawn = Math.max(head.drawn, to)
        if (to >= root.rows) root.heads[c] = null
      }
    }
  }

  Timer {
    id: timer
    interval: root.frameMs
    repeat: true
    onTriggered: {
      root.frames++
      var moving = false
      // a stuck drop must not keep the timer alive: past developMs everything lands
      var overdue = root.frames * root.frameMs > root.developMs
      for (var c = 0; c < root.heads.length; c++) {
        var head = root.heads[c]
        if (!head) continue
        head.y = overdue ? root.rows : head.y + head.speed
        moving = true
      }
      if (!moving) stop()
      canvas.requestPaint()
    }
  }
}

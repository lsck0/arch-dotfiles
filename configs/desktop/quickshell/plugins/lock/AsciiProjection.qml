import QtQuick
import qs.Commons

/**
 * AsciiProjection: the lock's wallpaper re-drawn as text (signature C).
 *
 * On each lock the wallpaper is sampled once into a grid of at most maxCols x maxRows cells (one
 * drawImage + getImageData), luminance picks a glyph from ramp and the pixel, nudged toward the
 * accent, colours it. A rain then develops the picture: each column's drop leaves the projected
 * glyphs behind it, and everything has landed after developMs. Once landed, a few drops keep
 * falling forever down random columns, each a bright accent head with a short fading trail over
 * the static projection (scaled by Style.fx.matrixRain; 0 / Power.saver leaves it static instead).
 *
 * Properties:
 *   image    a decoded Image item of the wallpaper (Lock.qml's blurred one)
 *   active   the lock surface is up; going false drops the sample
 *   animate  rain; false draws the end state at once
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
  // continuous rain after the reveal: a drop traverses the grid in rainFallMs, trail up to rainTrail cells
  readonly property int rainFallMs: 2600
  readonly property int rainTrail: 10

  readonly property real cellH: Math.max(height / maxRows, Style.font.caption)
  readonly property real cellW: Math.max(width / maxCols, cellH * glyphAspect)
  readonly property int cols: Math.max(1, Math.floor(width / cellW))
  readonly property int rows: Math.max(1, Math.floor(height / cellH))

  // sampled grid, row-major; null until the next paint samples it
  property var glyphs: null
  property var colors: null
  // per column: { y: head row, speed: rows per frame, drawn: last row drawn as head }
  property var heads: []
  // continuous-rain drops: { c: column, y: head row, speed: rows per frame, len: trail length }
  property var rain: []
  property int frames: 0

  function project() {
    timer.stop()
    root.glyphs = null
    root.colors = null
    root.heads = []
    root.rain = []
    // drop any cached pixels so a changed wallpaper re-decodes
    if (root.image && root.image.source) canvas.unloadImage(root.image.source)
    canvas.requestPaint()
  }


  onActiveChanged: {
    if (active) project()
    else {
      timer.stop()
      root.glyphs = null
      root.colors = null
      root.rain = []
    }
  }
  onColsChanged: if (active) project()
  onRowsChanged: if (active) project()
  // power saver flipping matrixRain/motion while locked switches between rain and static end-state
  onAnimateChanged: if (active) project()

  Connections {
    target: root.image
    function onStatusChanged() { if (root.active) root.project() }
  }

  Canvas {
    id: canvas
    anchors.fill: parent

    onImageLoaded: requestPaint()

    function sample(ctx) {
      ctx.clearRect(0, 0, width, height)
      // qt6.12 draws nothing from an Image item; draw its source url instead (loaded below)
      ctx.drawImage(root.image.source, 0, 0, root.cols, root.rows)
      var data = ctx.getImageData(0, 0, root.cols, root.rows).data
      ctx.clearRect(0, 0, root.cols, root.rows)
      var acc = Colors.accent
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
        ctx.fillStyle = Colors.accent
        glyph = glyph === " " ? "." : glyph
      } else {
        if (glyph === " ") return
        ctx.fillStyle = root.colors[r * root.cols + c]
      }
      ctx.fillText(glyph, x, y)
    }

    // one continuous-rain cell: a projection glyph lit to style; forceDot shows a drop over empty space
    function raincell(ctx, c, r, style, forceDot) {
      var x = c * root.cellW, y = r * root.cellH
      ctx.clearRect(x, y, root.cellW, root.cellH)
      var glyph = root.glyphs[r * root.cols + c]
      if (glyph === " ") { if (!forceDot) return; glyph = "." }
      ctx.fillStyle = style
      ctx.fillText(glyph, x, y)
    }

    // redraw each drop's trail window over the static projection; cells it has left restore to base
    function rainPaint(ctx) {
      var acc = Colors.accent
      for (var i = 0; i < root.rain.length; i++) {
        var d = root.rain[i]
        var hr = Math.floor(d.y)
        for (var r = hr - d.len - 2; r <= hr; r++) {
          if (r < 0 || r >= root.rows) continue
          var dist = hr - r
          if (dist <= 0) { raincell(ctx, d.c, r, acc, true); continue }
          if (dist <= d.len) {
            var t = dist / d.len
            var bc = root.colors[r * root.cols + d.c]
            raincell(ctx, d.c, r, Qt.rgba(acc.r + (bc.r - acc.r) * t, acc.g + (bc.g - acc.g) * t, acc.b + (bc.b - acc.b) * t, 1), false)
          } else {
            cell(ctx, d.c, r, false)
          }
        }
      }
    }

    onPaint: {
      var ctx = getContext("2d")
      if (!root.glyphs) {
        // nothing to show yet, and nothing of the last lock either
        if (!root.active || !root.image || root.image.status !== Image.Ready) {
          ctx.clearRect(0, 0, width, height)
          return
        }
        // the canvas needs the source url loaded before drawImage can read its pixels
        if (!isImageLoaded(root.image.source)) { loadImage(root.image.source); return }
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
      rainPaint(ctx)
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
      // once the develop has landed, keep a handful of drops raining down random columns forever
      if (root.animate && overdue) {
        var intensity = Style.fx.matrixRain
        var maxDrops = Math.max(1, Math.round(intensity * 24))
        var fall = root.rows * root.frameMs / root.rainFallMs
        var next = []
        for (var d = 0; d < root.rain.length; d++) {
          var drop = root.rain[d]
          drop.y += drop.speed
          if (drop.y - drop.len <= root.rows) next.push(drop)
        }
        if (next.length < maxDrops && Math.random() < intensity * 0.3)
          next.push({ c: Math.floor(Math.random() * root.cols), y: 0,
                      speed: fall * (0.7 + Math.random() * 0.6),
                      len: 6 + Math.floor(Math.random() * (root.rainTrail - 6)) })
        root.rain = next
        moving = true
      }
      if (!moving) stop()
      canvas.requestPaint()
    }
  }
}

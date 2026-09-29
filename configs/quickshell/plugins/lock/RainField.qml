import QtQuick
import qs.Commons

// Digital-rain field, ported from the matrixrain screensaver so the lock IS the
// rain. Self-contained: drives its own paint + advance timers while `running`.
Item {
  id: root
  property bool running: true

  // Opaque backdrop so nothing underneath shows through.
  Rectangle { anchors.fill: parent; color: Color.background }

  Canvas {
    id: rain
    anchors.fill: parent
    renderTarget: Canvas.FramebufferObject

    // Per-column head row and fall speed; rebuilt when the grid size changes.
    property var drops: []
    property int cell: Math.max(Style.space(12), Style.font.body)
    property int cols: Math.max(1, Math.floor(width / cell))
    property int rows: Math.max(1, Math.floor(height / cell))
    // ASCII-only glyph pool.
    readonly property string charset: "01<>[]{}/\\|=+-*!?$#@abcdef0123456789"
    readonly property int trail: 16

    function reseed() {
      var d = []
      for (var c = 0; c < cols; c++)
        d.push({ y: -Math.floor(Math.random() * rows), speed: 0.4 + Math.random() * 0.9 })
      drops = d
    }
    function glyph() { return charset.charAt(Math.floor(Math.random() * charset.length)) }

    onColsChanged: reseed()
    Component.onCompleted: reseed()

    onPaint: {
      var ctx = getContext("2d")
      // Fade the previous frame toward the background: fading trails, only new heads.
      var bg = Color.background
      ctx.fillStyle = Qt.rgba(bg.r, bg.g, bg.b, 0.14)
      ctx.fillRect(0, 0, width, height)
      var lead = Qt.lighter(Color.accent, 1.7)
      ctx.fillStyle = Qt.rgba(lead.r, lead.g, lead.b, 1)
      ctx.font = cell + "px " + Style.font.family
      ctx.textBaseline = "top"
      var density = Style.fx.matrixRain
      for (var i = 0; i < drops.length; i++) {
        if ((i % 7) / 7 > density + 0.02) continue
        var ry = Math.floor(drops[i].y)
        if (ry < 0 || ry > rows) continue
        ctx.fillText(glyph(), i * cell, ry * cell)
      }
    }
  }

  // Advances every column head and repaints; a spent column respawns at the top.
  Timer {
    interval: 90
    running: root.running
    repeat: true
    onTriggered: {
      var d = rain.drops
      for (var i = 0; i < d.length; i++) {
        d[i].y += d[i].speed
        if (d[i].y - rain.trail > rain.rows && Math.random() > 0.975) {
          d[i].y = -Math.floor(Math.random() * 8)
          d[i].speed = 0.4 + Math.random() * 0.9
        }
      }
      rain.requestPaint()
    }
  }
}

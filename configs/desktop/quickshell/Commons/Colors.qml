pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// wallpaper-derived palette
QtObject {
  id: root

  readonly property string home: Quickshell.env("HOME")
  // wallust keeps pywal's path and schema
  readonly property string colorsPath: home + "/.cache/wal/colors.json"

  // every role binds to these six, so animating them animates all
  property color foreground: "#bfbdb6"
  property color background: "#0b0e14"
  property color accent: "#39bae6"
  // second palette colour, the one hue-farthest from accent
  property color accent2: "#ffb454"
  // hue-separated from accent, see conditionPalette
  property color urgent: "#f07178"
  property color muted: "#565b66"

  // raised fills: panels, cards, toasts
  readonly property color surface: raise(background, surfaceLift)
  readonly property real surfaceLift: 0.04

  // fixed hues tinted toward accent so they sit in the palette
  readonly property real semanticTint: 0.15
  readonly property color warn: Qt.tint(warnBase, Util.alpha(accent, semanticTint))
  readonly property color ok: Qt.tint(okBase, Util.alpha(accent, semanticTint))
  readonly property color severe: Qt.tint(severeBase, Util.alpha(accent, semanticTint))
  readonly property color warnBase: "#e8c317"
  readonly property color okBase: "#23a55a"
  readonly property color severeBase: "#e67e22"

  // severity ramp, t in 0..1: accent, warn, severe, urgent at rampStops
  readonly property var rampStops: [0, 0.5, 0.75, 1]
  function ramp(t) {
    var stops = [accent, warn, severe, urgent]
    var x = Math.max(0, Math.min(1, Number(t) || 0))
    for (var i = 1; i < rampStops.length; i++) {
      if (x <= rampStops[i]) {
        var f = (x - rampStops[i - 1]) / (rampStops[i] - rampStops[i - 1])
        var a = stops[i - 1], b = stops[i]
        return Qt.rgba(a.r + (b.r - a.r) * f, a.g + (b.g - a.g) * f, a.b + (b.b - a.b) * f, 1)
      }
    }
    return urgent
  }

  function raise(c, amount) {
    return Qt.hsva(c.hsvHue < 0 ? 0 : c.hsvHue, c.hsvSaturation, Math.min(1, c.hsvValue + amount), 1)
  }

  // conditioning so any wallpaper yields a legible ui
  function toneMap(c, lo, hi) {
    var v = Math.max(lo, Math.min(hi, c.hsvValue))
    return Qt.hsva(c.hsvHue < 0 ? 0 : c.hsvHue, c.hsvSaturation, v, 1)
  }

  function vivify(c, minSat, minVal) {
    return Qt.hsva(c.hsvHue < 0 ? 0 : c.hsvHue,
                   Math.max(minSat, c.hsvSaturation),
                   Math.max(minVal, c.hsvValue), 1)
  }

  // nudge hue toward green by amount
  function phosphor(c, amount) {
    if (!amount) return c
    var h = c.hsvHue < 0 ? 0.333 : c.hsvHue
    var d = 0.333 - h
    if (d > 0.5) d -= 1; else if (d < -0.5) d += 1
    var nh = h + d * amount
    if (nh < 0) nh += 1; else if (nh > 1) nh -= 1
    return Qt.hsva(nh, c.hsvSaturation, c.hsvValue, 1)
  }

  // wcag luminance and contrast
  function _lum(c) {
    function ch(v) { return v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4) }
    return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b)
  }
  function contrast(a, b) {
    var la = _lum(a), lb = _lum(b)
    return (Math.max(la, lb) + 0.05) / (Math.min(la, lb) + 0.05)
  }

  function legible(c, bg, ratio) {
    var target = ratio || 3.0
    var out = c
    for (var i = 0; i < 12 && contrast(out, bg) < target; i++)
      out = Qt.tint(out, Qt.rgba(1, 1, 1, 0.18))
    return out
  }

  // hue in degrees, achromatic reads as 0
  function _hue(c) { return (c.hsvHue < 0 ? 0 : c.hsvHue) * 360 }
  // signed shortest turn from a to b, degrees
  function _turn(a, b) { return ((b - a) % 360 + 540) % 360 - 180 }
  function _withHue(c, deg) { return Qt.hsva(((deg % 360) + 360) % 360 / 360, c.hsvSaturation, c.hsvValue, 1) }

  // urgent must not read as accent: within urgentMinApart it turns up to urgentMaxTurn toward red,
  // and if accent itself is red it is pushed to urgentMinApart on the far side
  readonly property real urgentMinApart: 40
  readonly property real urgentMaxTurn: 20
  function separateUrgent(u, a) {
    var uh = _hue(u), ah = _hue(a)
    if (Math.abs(_turn(ah, uh)) >= urgentMinApart) return u
    var toRed = _turn(uh, 0)
    uh += (toRed < 0 ? -1 : 1) * Math.min(urgentMaxTurn, Math.abs(toRed))
    var apart = _turn(ah, uh)
    if (Math.abs(apart) < urgentMinApart) uh = ah + (apart < 0 ? -urgentMinApart : urgentMinApart)
    return _withHue(u, uh)
  }

  // farthest hue from accent among candidates that pass contrast; else the farthest lifted to pass
  readonly property real accent2Contrast: 3.0
  function pickAccent2(candidates, acc, bg) {
    var best = null, bestDist = -1, passing = null, passDist = -1
    for (var i = 0; i < candidates.length; i++) {
      var c = candidates[i]
      var d = Math.abs(_turn(_hue(acc), _hue(c)))
      if (d > bestDist) { best = c; bestDist = d }
      if (d > passDist && contrast(c, bg) >= accent2Contrast) { passing = c; passDist = d }
    }
    if (passing) return passing
    if (best) return legible(best, bg, accent2Contrast)
    return legible(_withHue(acc, _hue(acc) + 180), bg, accent2Contrast)
  }

  /**
   * Pure: wallust colors.json text (or its parsed object) to the conditioned palette, no side effects.
   * Missing entries keep the matching field of `fallback`. verdict is "OK" when foreground and accent
   * meet their contrast targets on background, else "LOW". Throws on invalid JSON. Used by applyColors
   * and the picker preview.
   */
  function conditionPalette(raw, fallback) {
    var parsed = typeof raw === "string" ? JSON.parse(raw || "{}") : (raw || {})
    var special = parsed.special || {}
    var colors = parsed.colors || {}
    var f = fallback || root
    var out = {}
    out.background = special.background
      ? toneMap(Qt.color(special.background), Theme.backgroundValueMin, Theme.backgroundValueMax) : f.background
    out.foreground = special.foreground
      ? legible(Qt.color(special.foreground), out.background, Theme.foregroundContrast) : f.foreground
    out.accent = colors.color4
      ? legible(phosphor(vivify(Qt.color(colors.color4), Theme.accentMinSaturation, Theme.accentMinValue),
                         Theme.phosphorBias), out.background, Theme.accentContrast) : f.accent
    var rawUrgent = colors.color1
      ? legible(vivify(Qt.color(colors.color1), Theme.urgentMinSaturation, Theme.urgentMinValue),
                out.background, Theme.urgentContrast) : f.urgent
    out.urgent = legible(separateUrgent(rawUrgent, out.accent), out.background, Theme.urgentContrast)
    // muted only floored, it must stay dim
    out.muted = colors.color8 ? legible(Qt.color(colors.color8), out.background, Theme.mutedContrast) : f.muted
    var pool = []
    for (var i = 1; i <= 6; i++)
      if (colors["color" + i]) pool.push(vivify(Qt.color(colors["color" + i]), Theme.accentMinSaturation, Theme.accentMinValue))
    out.accent2 = pool.length > 0 ? pickAccent2(pool, out.accent, out.background) : f.accent2
    out.surface = raise(out.background, surfaceLift)
    out.verdict = contrast(out.foreground, out.background) >= Theme.foregroundContrast
      && contrast(out.accent, out.background) >= Theme.accentContrast ? "OK" : "LOW"
    return out
  }

  // off until the first load so startup does not fade
  property bool animatePalette: false

  Behavior on foreground { enabled: root.animatePalette && !Power.saver; ColorAnimation { duration: Theme.paletteTransitionMs; easing.type: Easing.InOutQuad } }
  Behavior on background { enabled: root.animatePalette && !Power.saver; ColorAnimation { duration: Theme.paletteTransitionMs; easing.type: Easing.InOutQuad } }
  Behavior on accent     { enabled: root.animatePalette && !Power.saver; ColorAnimation { duration: Theme.paletteTransitionMs; easing.type: Easing.InOutQuad } }
  Behavior on accent2    { enabled: root.animatePalette && !Power.saver; ColorAnimation { duration: Theme.paletteTransitionMs; easing.type: Easing.InOutQuad } }
  Behavior on urgent     { enabled: root.animatePalette && !Power.saver; ColorAnimation { duration: Theme.paletteTransitionMs; easing.type: Easing.InOutQuad } }
  Behavior on muted      { enabled: root.animatePalette && !Power.saver; ColorAnimation { duration: Theme.paletteTransitionMs; easing.type: Easing.InOutQuad } }

  // fixed colours, never follow the wallpaper
  readonly property QtObject semantic: QtObject {
    id: semanticColors

    property color live: "#c0392b"
    property color recording: root.severeBase
    // tinted roles, kept here for the status users
    property color warn: root.warn
    property color speaking: root.okBase

    // meteoalarm levels 4 and 3, level 2 is warn
    property color alertRed: semanticColors.live
    property color alertOrange: semanticColors.recording
  }

  // shared scrim for full-screen overlays
  readonly property color scrim: Util.alpha(root.background, Style.translucency.scrim)
  // floating surfaces over layer blur
  readonly property color panelFill: Util.alpha(root.surface, Style.translucency.panel)
  readonly property color overlayFill: Util.alpha(root.surface, Style.translucency.overlay)

  readonly property QtObject bar: QtObject {
    property color background: Util.alpha(root.background, Style.translucency.bar)
    property color text: root.foreground
    property color active: root.urgent
  }
  readonly property QtObject popups: QtObject {
    property color text: root.foreground
    property color border: Util.alpha(root.accent, 1.0)
  }
  readonly property QtObject tooltip: QtObject {
    property color background: root.panelFill
    property color text: root.foreground
    property color border: Util.alpha(root.foreground, 1.0)
  }
  readonly property QtObject notifications: QtObject {
    property color background: root.panelFill
    property color text: root.foreground
    property color border: Util.alpha(root.accent, 1.0)
  }
  readonly property QtObject menu: QtObject {
    property color background: root.panelFill
    property color text: root.foreground
    property color border: Util.alpha(root.foreground, 1.0)
    property color scrim: root.scrim
    // matches Style.selectedFillAlpha
    property color selectedBackground: Util.alpha(root.accent, 0.22)
    property color selectedText: root.accent
  }
  readonly property QtObject imagePicker: QtObject {
    property color scrim: root.scrim
    property color text: root.foreground
    property color selectedBorder: Util.alpha(root.accent, 1.0)
    property color unselectedBorder: Util.alpha(root.foreground, 0.28)
  }

  // kept so a theme.json edit can re-condition
  property string rawColors: ""

  // a new wallpaper palette landed (not the first load, not a theme.json re-condition): the OSD sync log
  signal paletteSynced(var p)

  // palette sync (signature D): Background.qml holds a new palette while its wedge is short of the
  // centre, so the crossfade starts as it passes; the hold lifts itself after syncHoldMaxMs
  property bool syncHold: false
  property var pendingPalette: null
  readonly property int syncHoldMaxMs: 3000
  onSyncHoldChanged: {
    if (syncHold) { holdTimer.restart(); return }
    holdTimer.stop()
    if (!pendingPalette) return
    var p = pendingPalette
    pendingPalette = null
    assign(p, true)
  }
  property Timer holdTimer: Timer {
    interval: root.syncHoldMaxMs
    onTriggered: root.syncHold = false
  }

  function assign(p, announce) {
    var changed = !Qt.colorEqual(p.background, background) || !Qt.colorEqual(p.accent, accent)
    background = p.background
    foreground = p.foreground
    accent = p.accent
    accent2 = p.accent2
    urgent = p.urgent
    muted = p.muted
    if (announce && changed) paletteSynced(p)
  }

  function applyColors(raw) {
    var fromFile = raw !== undefined
    if (fromFile) rawColors = raw || ""
    try {
      var p = conditionPalette(rawColors)
      if (fromFile && root.animatePalette && root.syncHold) {
        pendingPalette = p
        return
      }
      assign(p, fromFile && root.animatePalette)
      if (!root.animatePalette) Qt.callLater(function () { root.animatePalette = true })
    } catch (e) {
      console.warn("colors.json parse failed:", e)
    }
  }

  property Connections themeWatch: Connections {
    target: Theme
    function onRevisionChanged() {
      if (root.rawColors) root.applyColors(undefined)
    }
  }

  property FileView colorsFile: FileView {
    id: colorsFile
    path: root.colorsPath
    watchChanges: true
    printErrors: false
    // defensive, wallust writes in place today
    onLoaded: {
      root.applyColors(text())
      Util.rearmWatch(this)
    }
    onFileChanged: reload()
  }
}

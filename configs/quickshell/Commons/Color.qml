pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// The palette.
QtObject {
  id: root

  readonly property string home: Quickshell.env("HOME")
  // Still ~/.cache/wal/ despite wallust having replaced pywal on 2026-09-03: wallust writes pywal's paths and schema deliberately, so every consumer in this repo kept working unchanged.
  readonly property string colorsPath: home + "/.cache/wal/colors.json"

  // Every one of the 40-odd role colours below is a binding on these five, so animating the roots animates the entire palette — five Behaviors instead of forty-four.
  property color foreground: "#c2c3c5"
  property color background: "#0b1019"
  property color accent: "#B68B74"
  property color urgent: "#62524F"
  property color muted: "#5a616e"

  // ---- palette conditioning (adapted from Ryoku's Wallust.qml) ---------- wallust reports whatever the wallpaper happens to contain, and some wallpapers are a bad basis for a UI: a bright one yields a background too light to read white-ish text on, a washed-out one yields an accent with no presence, and either can put accent and surface close enough together that selected text disappears. These three functions are the conditioning layer that makes any wallpaper safe, applied in applyColors() below. The extraction backend is untouched — this is math on wallust's own colors.json, not a replacement for it. Their thresholds are Theme.qml properties rather than literals, because "how dark should any wallpaper be forced" is a taste decision that belongs to the user, not to this file.

  // Force a colour into a value band, keeping its hue and saturation.
  function toneMap(c, lo, hi) {
    var v = Math.max(lo, Math.min(hi, c.hsvValue))
    return Qt.hsva(c.hsvHue < 0 ? 0 : c.hsvHue, c.hsvSaturation, v, 1)
  }

  // Floor an accent's saturation and value so a muted wallpaper still gets an accent with presence instead of a grey smudge.
  function vivify(c, minSat, minVal) {
    return Qt.hsva(c.hsvHue < 0 ? 0 : c.hsvHue,
                   Math.max(minSat, c.hsvSaturation),
                   Math.max(minVal, c.hsvValue), 1)
  }

  // Nudge a colour's hue toward matrix-green (120deg) by `amount`, keeping sat/value.
  function phosphor(c, amount) {
    if (!amount) return c
    var h = c.hsvHue < 0 ? 0.333 : c.hsvHue
    var d = 0.333 - h
    if (d > 0.5) d -= 1; else if (d < -0.5) d += 1
    var nh = h + d * amount
    if (nh < 0) nh += 1; else if (nh > 1) nh -= 1
    return Qt.hsva(nh, c.hsvSaturation, c.hsvValue, 1)
  }

  // WCAG relative luminance, then contrast ratio.
  function _lum(c) {
    function ch(v) { return v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4) }
    return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b)
  }
  function contrast(a, b) {
    var la = _lum(a), lb = _lum(b)
    return (Math.max(la, lb) + 0.05) / (Math.min(la, lb) + 0.05)
  }

  // Walk `c` toward white in ~18% steps until it clears `ratio` against `bg`.
  function legible(c, bg, ratio) {
    var target = ratio || 3.0
    var out = c
    for (var i = 0; i < 12 && contrast(out, bg) < target; i++)
      out = Qt.tint(out, Qt.rgba(1, 1, 1, 0.18))
    return out
  }

  // Off until the first palette load lands.
  property bool animatePalette: false

  Behavior on foreground { enabled: root.animatePalette; ColorAnimation { duration: Theme.paletteTransitionMs; easing.type: Easing.InOutQuad } }
  Behavior on background { enabled: root.animatePalette; ColorAnimation { duration: Theme.paletteTransitionMs; easing.type: Easing.InOutQuad } }
  Behavior on accent     { enabled: root.animatePalette; ColorAnimation { duration: Theme.paletteTransitionMs; easing.type: Easing.InOutQuad } }
  Behavior on urgent     { enabled: root.animatePalette; ColorAnimation { duration: Theme.paletteTransitionMs; easing.type: Easing.InOutQuad } }
  Behavior on muted      { enabled: root.animatePalette; ColorAnimation { duration: Theme.paletteTransitionMs; easing.type: Easing.InOutQuad } }

  // The offset shadow's colour.
  readonly property color shadow: Qt.darker(root.background, 3.0)

  // ---- semantic colours --------------------------------------------------- The one set of colours that must NOT follow the wallpaper.
  readonly property QtObject semantic: QtObject {
    id: semanticColors

    // Broadcast/record conventions, as used by cameras and broadcast desks.
    property color live: "#c0392b"
    property color recording: "#e67e22"
    // Degraded-but-not-failed: dropped frames, congestion, a reconnecting stream.
    property color warn: "#e8c317"
    // Discord's own speaking indicator.
    property color speaking: "#23a55a"

    // MeteoAlarm awareness levels 4 and 3; level 2 is `warn` above.
    property color alertRed: semanticColors.live
    property color alertOrange: semanticColors.recording
  }

  // ONE SCRIM FOR EVERY FULL-SCREEN OVERLAY.
  readonly property color scrim: Util.alpha(root.background, 0.75)

  readonly property QtObject bar: QtObject {
    property color background: Util.alpha(root.background, 1.0)
    property color text: root.foreground
    property color active: root.urgent
  }
  readonly property QtObject popups: QtObject {
    property color background: Util.alpha(root.background, 1.0)
    property color text: root.foreground
    property color border: Util.alpha(root.accent, 1.0)
  }
  readonly property QtObject tooltip: QtObject {
    property color background: Util.alpha(root.background, 1.0)
    property color text: root.foreground
    property color border: Util.alpha(root.foreground, 1.0)
  }
  readonly property QtObject notifications: QtObject {
    property color background: Util.alpha(root.background, 1.0)
    property color text: root.foreground
    property color border: Util.alpha(root.accent, 1.0)
    property color countdown: root.accent
  }
  readonly property QtObject menu: QtObject {
    property color background: Util.alpha(root.background, 1.0)
    property color text: root.foreground
    property color border: Util.alpha(root.foreground, 1.0)
    // Points at the shared overlay scrim above; every full-screen surface in the shell dims the desktop by the same amount.
    property color scrim: root.scrim
    // Accent-tinted, matching Style.selectedFillAlpha's weight.
    property color selectedBackground: Util.alpha(root.accent, 0.22)
    property color selectedText: root.accent
    property color selectedBorder: Util.alpha(root.foreground, 0.0)
  }
  readonly property QtObject polkit: QtObject {
    property color background: Util.alpha(root.background, 1.0)
    property color text: root.foreground
    property color textError: root.urgent
    property color border: Util.alpha(root.accent, 1.0)
    property color borderError: Util.alpha(root.urgent, 1.0)
    property color accent: root.accent
    property color scrim: Util.alpha(root.background, 0.5)
  }
  readonly property QtObject lock: QtObject {
    property color background: Util.alpha(root.background, 0.8)
    property color text: root.foreground
    property color placeholder: Util.alpha(root.foreground, 0.66)
    property color textError: root.urgent
    property color border: Util.alpha(root.foreground, 1.0)
    property color borderActive: Util.alpha(root.accent, 1.0)
    property color borderError: Util.alpha(root.urgent, 1.0)
    property color selection: Util.alpha(root.accent, 0.45)
  }
  readonly property QtObject imagePicker: QtObject {
    // The value the shared scrim was settled on — this surface is why.
    property color scrim: root.scrim
    property color text: root.foreground
    property color selectedBorder: Util.alpha(root.accent, 1.0)
    property color unselectedBorder: Util.alpha(root.foreground, 0.28)
  }

  // Kept so a theme.json edit can re-condition the palette already in hand.
  property string rawColors: ""

  function applyColors(raw) {
    if (raw !== undefined) rawColors = raw || ""
    try {
      var parsed = JSON.parse(rawColors || "{}")
      var special = parsed.special || {}
      var colors = parsed.colors || {}
      // Condition the raw wallust values rather than binding them straight through.
      if (special.background)
        background = toneMap(Qt.color(special.background),
                             Theme.backgroundValueMin, Theme.backgroundValueMax)
      if (special.foreground)
        foreground = legible(Qt.color(special.foreground), background, Theme.foregroundContrast)
      if (colors.color4)
        accent = legible(phosphor(vivify(Qt.color(colors.color4),
                                Theme.accentMinSaturation, Theme.accentMinValue),
                                Theme.phosphorBias),
                         background, Theme.accentContrast)
      // Urgent keeps its hue but must also be visible; it carries meaning.
      if (colors.color1)
        urgent = legible(vivify(Qt.color(colors.color1),
                                Theme.urgentMinSaturation, Theme.urgentMinValue),
                         background, Theme.urgentContrast)
      // Muted is deliberately NOT forced to a legible ratio — it is the de-emphasis role, and dragging it to 3:1 would defeat its only job.
      if (colors.color8)
        muted = legible(Qt.color(colors.color8), background, Theme.mutedContrast)
      // Enable only after the first real palette is in place, so the startup jump from the defaults is instant and every later wallpaper change crossfades.
      if (!root.animatePalette) Qt.callLater(function () { root.animatePalette = true })
    } catch (e) {
      console.warn("colors.json parse failed:", e)
    }
  }

  // Re-condition on a theme.json edit, using the colors.json already read.
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
    // Defensive rather than load-bearing: wallust rewrites colors.json in place today (verified), so this watch survives without the re-arm.
    onLoaded: {
      root.applyColors(text())
      Util.rearmWatch(this)
    }
    onFileChanged: reload()
  }
}

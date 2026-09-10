pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// The palette. Same surface-role shape as omarchy-shell's Color.qml
// (bar/popups/tooltip/notifications/menu/polkit/lock/imagePicker, each
// composed from the foundational palette via alpha rather than aliased to
// flat colours) — but fed straight from pywal's colors.json instead of
// theme/colors.toml + shell.toml.
//
// There is exactly ONE colour source here: the current wallpaper, via
// pywal/wallust (scripts/switch-wallpaper.sh). No named-theme list, no
// swappable palettes. What is user-configurable is how that source is
// *interpreted* — the conditioning constants below all come from
// Theme.qml/theme.json and re-apply live.
QtObject {
  id: root

  readonly property string home: Quickshell.env("HOME")
  readonly property string colorsPath: home + "/.cache/wal/colors.json"

  // Every one of the 40-odd role colours below is a binding on these five,
  // so animating the roots animates the entire palette — five Behaviors
  // instead of forty-four.
  //
  // The wallpaper already crossfades (plugins/background/Background.qml)
  // while the colours used to snap the instant colors.json changed, which
  // read as a glitch rather than a transition. Roughly matched to the
  // background reveal.
  property color foreground: "#c2c3c5"
  property color background: "#0b1019"
  property color accent: "#B68B74"
  property color urgent: "#62524F"
  property color muted: "#5a616e"

  // ---- palette conditioning (adapted from Ryoku's Wallust.qml) ----------
  //
  // pywal reports whatever the wallpaper happens to contain, and some
  // wallpapers are a bad basis for a UI: a bright one yields a background
  // too light to read white-ish text on, a washed-out one yields an accent
  // with no presence, and either can put accent and surface close enough
  // together that selected text disappears. These three functions are the
  // conditioning layer that makes any wallpaper safe, applied in
  // applyColors() below. The extraction backend is untouched — this is math
  // on pywal's own colors.json, not a replacement for it.
  //
  // Their thresholds are Theme.qml properties rather than literals, because
  // "how dark should any wallpaper be forced" is a taste decision that
  // belongs to the user, not to this file.

  // Force a colour into a value band, keeping its hue and saturation. This
  // is what stops a bright wallpaper producing an unreadable shell.
  function toneMap(c, lo, hi) {
    var v = Math.max(lo, Math.min(hi, c.hsvValue))
    return Qt.hsva(c.hsvHue < 0 ? 0 : c.hsvHue, c.hsvSaturation, v, 1)
  }

  // Floor an accent's saturation and value so a muted wallpaper still gets
  // an accent with presence instead of a grey smudge.
  function vivify(c, minSat, minVal) {
    return Qt.hsva(c.hsvHue < 0 ? 0 : c.hsvHue,
                   Math.max(minSat, c.hsvSaturation),
                   Math.max(minVal, c.hsvValue), 1)
  }

  // WCAG relative luminance, then contrast ratio. Real math rather than a
  // brightness eyeball, because the whole point is a guarantee.
  function _lum(c) {
    function ch(v) { return v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4) }
    return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b)
  }
  function contrast(a, b) {
    var la = _lum(a), lb = _lum(b)
    return (Math.max(la, lb) + 0.05) / (Math.min(la, lb) + 0.05)
  }

  // Walk `c` toward white in ~18% steps until it clears `ratio` against
  // `bg`. Capped so a pathological pair terminates instead of looping; at
  // that point the lightened colour is still the best available answer.
  function legible(c, bg, ratio) {
    var target = ratio || 3.0
    var out = c
    for (var i = 0; i < 12 && contrast(out, bg) < target; i++)
      out = Qt.tint(out, Qt.rgba(1, 1, 1, 0.18))
    return out
  }

  // Off until the first palette load lands. Otherwise every shell start
  // would visibly animate from these hardcoded defaults to the real
  // wallpaper colours.
  property bool animatePalette: false

  Behavior on foreground { enabled: root.animatePalette; ColorAnimation { duration: Theme.paletteTransitionMs; easing.type: Easing.InOutQuad } }
  Behavior on background { enabled: root.animatePalette; ColorAnimation { duration: Theme.paletteTransitionMs; easing.type: Easing.InOutQuad } }
  Behavior on accent     { enabled: root.animatePalette; ColorAnimation { duration: Theme.paletteTransitionMs; easing.type: Easing.InOutQuad } }
  Behavior on urgent     { enabled: root.animatePalette; ColorAnimation { duration: Theme.paletteTransitionMs; easing.type: Easing.InOutQuad } }
  Behavior on muted      { enabled: root.animatePalette; ColorAnimation { duration: Theme.paletteTransitionMs; easing.type: Easing.InOutQuad } }

  // The offset shadow's colour. A palette role rather than a flat black:
  // over a warm wallpaper a pure-black slab reads as a hole, while a colour
  // pushed down from the background stays coherent with it. Alpha is applied
  // at the draw site from Style.shadowAlpha.
  readonly property color shadow: Qt.darker(root.background, 3.0)

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
    // 0.94, up from 0.88 (was 0.5 originally). Still legible enough to
    // recognize the desktop behind, but the modal is unmistakably the thing
    // in focus rather than a small overlay floating on a busy screen.
    property color scrim: Util.alpha(root.background, 0.94)
    // Accent-tinted, matching Style.selectedFillAlpha's weight. Written as a
    // literal rather than read from Style so this file stays free of a
    // Color->Style->Color import cycle; Style is the only direction that
    // reaches across.
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
    // Deliberately lighter than menu.scrim: this one sits behind a wallpaper
    // grid, where seeing the desktop through it is the point. 0.75, up from
    // 0.6.
    property color scrim: Util.alpha(root.background, 0.75)
    property color text: root.foreground
    property color selectedBorder: Util.alpha(root.accent, 1.0)
    property color unselectedBorder: Util.alpha(root.foreground, 0.28)
  }

  // Kept so a theme.json edit can re-condition the palette already in hand.
  // Without this, changing a conditioning knob did nothing visible until the
  // next wallpaper change rewrote colors.json — which looks exactly like the
  // knob not working.
  property string rawColors: ""

  function applyColors(raw) {
    if (raw !== undefined) rawColors = raw || ""
    try {
      var parsed = JSON.parse(rawColors || "{}")
      var special = parsed.special || {}
      var colors = parsed.colors || {}
      // Condition the raw pywal values rather than binding them straight
      // through. Order matters: the background has to settle first, because
      // both the foreground and the accent are made legible *against it*.
      if (special.background)
        background = toneMap(Qt.color(special.background),
                             Theme.backgroundValueMin, Theme.backgroundValueMax)
      if (special.foreground)
        foreground = legible(Qt.color(special.foreground), background, Theme.foregroundContrast)
      if (colors.color4)
        accent = legible(vivify(Qt.color(colors.color4),
                                Theme.accentMinSaturation, Theme.accentMinValue),
                         background, Theme.accentContrast)
      // Urgent keeps its hue but must also be visible; it carries meaning.
      if (colors.color1)
        urgent = legible(vivify(Qt.color(colors.color1),
                                Theme.urgentMinSaturation, Theme.urgentMinValue),
                         background, Theme.urgentContrast)
      // Muted is deliberately NOT forced to a legible ratio — it is the
      // de-emphasis role, and dragging it to 3:1 would defeat its only job.
      // Floored just enough to stay perceptible.
      if (colors.color8)
        muted = legible(Qt.color(colors.color8), background, Theme.mutedContrast)
      // Enable only after the first real palette is in place, so the
      // startup jump from the defaults is instant and every later
      // wallpaper change crossfades.
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
    // Defensive rather than load-bearing: wallust rewrites colors.json in
    // place today (verified), so this watch survives without the re-arm. It
    // is here so the two config watches in this shell do not differ by luck —
    // the day the palette generator switches to an atomic write, the colours
    // would otherwise just quietly stop following the wallpaper.
    onLoaded: {
      root.applyColors(text())
      Util.rearmWatch(this)
    }
    onFileChanged: reload()
  }
}

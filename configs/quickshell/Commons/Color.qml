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

  // every role binds to these five, so animating them animates all
  property color foreground: "#bfbdb6"
  property color background: "#0b0e14"
  property color accent: "#39bae6"
  property color urgent: "#f07178"
  property color muted: "#565b66"

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

  // off until the first load so startup does not fade
  property bool animatePalette: false

  Behavior on foreground { enabled: root.animatePalette; ColorAnimation { duration: Theme.paletteTransitionMs; easing.type: Easing.InOutQuad } }
  Behavior on background { enabled: root.animatePalette; ColorAnimation { duration: Theme.paletteTransitionMs; easing.type: Easing.InOutQuad } }
  Behavior on accent     { enabled: root.animatePalette; ColorAnimation { duration: Theme.paletteTransitionMs; easing.type: Easing.InOutQuad } }
  Behavior on urgent     { enabled: root.animatePalette; ColorAnimation { duration: Theme.paletteTransitionMs; easing.type: Easing.InOutQuad } }
  Behavior on muted      { enabled: root.animatePalette; ColorAnimation { duration: Theme.paletteTransitionMs; easing.type: Easing.InOutQuad } }

  // fixed colours, never follow the wallpaper
  readonly property QtObject semantic: QtObject {
    id: semanticColors

    property color live: "#c0392b"
    property color recording: "#e67e22"
    property color warn: "#e8c317"
    property color speaking: "#23a55a"

    // meteoalarm levels 4 and 3, level 2 is warn
    property color alertRed: semanticColors.live
    property color alertOrange: semanticColors.recording
  }

  // shared scrim for full-screen overlays
  readonly property color scrim: Util.alpha(root.background, 0.75)

  readonly property QtObject bar: QtObject {
    property color background: Util.alpha(root.background, 1.0)
    property color text: root.foreground
    property color active: root.urgent
  }
  readonly property QtObject popups: QtObject {
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
  }
  readonly property QtObject menu: QtObject {
    property color background: Util.alpha(root.background, 1.0)
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

  function applyColors(raw) {
    if (raw !== undefined) rawColors = raw || ""
    try {
      var parsed = JSON.parse(rawColors || "{}")
      var special = parsed.special || {}
      var colors = parsed.colors || {}
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
      if (colors.color1)
        urgent = legible(vivify(Qt.color(colors.color1),
                                Theme.urgentMinSaturation, Theme.urgentMinValue),
                         background, Theme.urgentContrast)
      // muted only floored, it must stay dim
      if (colors.color8)
        muted = legible(Qt.color(colors.color8), background, Theme.mutedContrast)
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

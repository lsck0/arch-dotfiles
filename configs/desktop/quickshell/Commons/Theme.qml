pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "Palette.js" as Palette

QtObject {
  id: root
  readonly property string path: Quickshell.shellDir + "/theme.json"
  // the font is a theme input beside the palette (configs/core/wallust/font.nu), set by a theme or toggle-font
  readonly property string fontPath: Paths.wal + "/font.json"
  readonly property string fontFamilyDefault: "Kode Mono"
  readonly property int fontSizeDefault: 13
  // every theme.json knob by its key: [section, default, min, max, integer]. A missing or invalid key takes the
  // default, so a deleted key reverts
  readonly property var knobs: ({
    "backgroundValueMin": ["palette", Palette.BG_VALUE_MIN, 0, 1],
    "backgroundValueMax": ["palette", Palette.BG_VALUE_MAX, 0, 1],
    "lightLuminance": ["palette", Palette.LIGHT_LUMINANCE, 0, 1],
    "foregroundContrast": ["palette", Palette.FOREGROUND_RATIO, 1, 21],
    "accentMinSaturation": ["palette", Palette.ACCENT_SATURATION_MIN, 0, 1],
    "accentMinValue": ["palette", Palette.ACCENT_VALUE_MIN, 0, 1],
    "accentContrast": ["palette", 3, 1, 21],
    "textContrast": ["palette", Palette.TEXT_RATIO, 1, 21],
    "urgentMinSaturation": ["palette", 0.55, 0, 1],
    "urgentMinValue": ["palette", 0.55, 0, 1],
    "urgentContrast": ["palette", 3, 1, 21],
    "semanticContrast": ["palette", 3, 1, 21],
    "mutedContrast": ["palette", 1.9, 1, 21],
    "transitionMs": ["palette", 600, 0, 5000, true],
    "glowStrength": ["fx", 0.55, 0, 1],
    "scanlineOpacity": ["fx", 0.06, 0, 0.3],
    "scanlineSpacing": ["fx", 3, 2, 8, true],
    "phosphorBias": ["fx", 0, 0, 1],
    "crtFlicker": ["fx", 0.02, 0, 0.1],
    "matrixRain": ["fx", 0.5, 0, 1]
  })
  // the knobs as theme.json sets them, plus fx.cornerBrackets
  property var values: knobValues({})
  property string fontFamily: fontFamilyDefault
  property int fontSize: fontSizeDefault
  property int revision: 0
  readonly property int reloadDelayMs: 80
  property FileView file
  property FileView fontFile
  property Timer reloadTimer
  property Timer fontReloadTimer

  file: FileView {
    path: root.path
    watchChanges: true
    printErrors: false
    onLoaded: {
      root.apply(text())
      Util.rearmWatch(this)
    }
    onFileChanged: root.reloadTimer.restart()
  }

  fontFile: FileView {
    path: root.fontPath
    watchChanges: true
    printErrors: false
    onLoaded: {
      root.applyFont(text())
      Util.rearmWatch(this)
    }
    onLoadFailed: root.applyFont("{}")
    onFileChanged: root.fontReloadTimer.restart()
  }

  reloadTimer: Timer {
    interval: root.reloadDelayMs
    onTriggered: root.file.reload()
  }

  fontReloadTimer: Timer {
    interval: root.reloadDelayMs
    onTriggered: root.fontFile.reload()
  }

  function _num(value, fallback, min, max) {
    var n = Number(value)
    if (!isFinite(n)) return fallback
    return Math.max(min, Math.min(max, n))
  }

  function knobValues(parsed) {
    var out = {}
    for (const key in knobs) {
      const [section, fallback, min, max, integer] = knobs[key]
      const n = _num((parsed[section] || {})[key], fallback, min, max)
      out[key] = integer ? Math.round(n) : n
    }
    out.backgroundValueMax = Math.max(out.backgroundValueMin, out.backgroundValueMax)
    const brackets = (parsed.fx || {}).cornerBrackets
    out.cornerBrackets = brackets === undefined || !!brackets
    return out
  }

  function applyFont(raw) {
    var font
    try {
      font = JSON.parse(raw || "{}")
    } catch (e) {
      return
    }
    if (!font || typeof font !== "object" || Array.isArray(font)) return
    fontFamily = (typeof font.family === "string" && font.family.trim().length > 0) ? font.family.trim() : fontFamilyDefault
    fontSize = Math.round(_num(font.size, fontSizeDefault, 6, 32))
    revision++
  }

  function apply(raw) {
    if (!String(raw || "").trim()) return
    var parsed
    try {
      parsed = JSON.parse(raw || "{}")
    } catch (e) {
      console.warn("theme.json parse failed, keeping previous theme:", e)
      return
    }
    if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
      console.warn("theme.json is not an object, keeping previous theme")
      return
    }
    values = knobValues(parsed)
    revision++
  }
}

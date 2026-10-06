pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// user knobs from theme.json, live-watched
QtObject {
  id: root

  readonly property string path: Quickshell.shellDir + "/theme.json"

  // ui/body family only, icons are pinned in Style
  property string fontFamily: "Kode Mono"
  // base px, the whole scale derives from it
  property int fontSize: 12

  // palette conditioning
  property real backgroundValueMin: 0.08
  property real backgroundValueMax: 0.26

  property real foregroundContrast: 7.0

  property real accentMinSaturation: 0.70
  property real accentMinValue: 0.62
  property real accentContrast: 3.0

  property real urgentMinSaturation: 0.55
  property real urgentMinValue: 0.55
  property real urgentContrast: 3.0

  // floor only, muted must stay dim
  property real mutedContrast: 1.9

  property int paletteTransitionMs: 600

  // fx, 0 disables each
  property real glowStrength: 0.55
  property real scanlineOpacity: 0.06
  property int  scanlineSpacing: 3
  property real phosphorBias: 0.0
  property bool cornerBrackets: true
  property real crtFlicker: 0.02
  property real matrixRain: 0.5

  // bumped on every (re)load
  property int revision: 0

  function _num(value, fallback, min, max) {
    var n = Number(value)
    if (!isFinite(n)) return fallback
    return Math.max(min, Math.min(max, n))
  }

  function apply(raw) {
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

    var font = parsed.font || {}
    if (typeof font.family === "string" && font.family.trim().length > 0)
      fontFamily = font.family.trim()
    if (font.size !== undefined) fontSize = Math.round(_num(font.size, fontSize, 6, 32))

    var p = parsed.palette || {}
    // floor first so a lone max still yields a valid band
    backgroundValueMin = _num(p.backgroundValueMin, backgroundValueMin, 0, 1)
    backgroundValueMax = Math.max(backgroundValueMin,
                                  _num(p.backgroundValueMax, backgroundValueMax, 0, 1))
    foregroundContrast = _num(p.foregroundContrast, foregroundContrast, 1, 21)
    accentMinSaturation = _num(p.accentMinSaturation, accentMinSaturation, 0, 1)
    accentMinValue = _num(p.accentMinValue, accentMinValue, 0, 1)
    accentContrast = _num(p.accentContrast, accentContrast, 1, 21)
    urgentMinSaturation = _num(p.urgentMinSaturation, urgentMinSaturation, 0, 1)
    urgentMinValue = _num(p.urgentMinValue, urgentMinValue, 0, 1)
    urgentContrast = _num(p.urgentContrast, urgentContrast, 1, 21)
    mutedContrast = _num(p.mutedContrast, mutedContrast, 1, 21)
    paletteTransitionMs = Math.round(_num(p.transitionMs, paletteTransitionMs, 0, 5000))

    var fx = parsed.fx || {}
    glowStrength = _num(fx.glowStrength, glowStrength, 0, 1)
    scanlineOpacity = _num(fx.scanlineOpacity, scanlineOpacity, 0, 0.3)
    scanlineSpacing = Math.round(_num(fx.scanlineSpacing, scanlineSpacing, 2, 8))
    phosphorBias = _num(fx.phosphorBias, phosphorBias, 0, 1)
    cornerBrackets = (fx.cornerBrackets === undefined) ? cornerBrackets : !!fx.cornerBrackets
    crtFlicker = _num(fx.crtFlicker, crtFlicker, 0, 0.1)
    matrixRain = _num(fx.matrixRain, matrixRain, 0, 1)

    revision++
  }

  property FileView file: FileView {
    path: root.path
    watchChanges: true
    // missing file is fine, defaults apply
    printErrors: false
    // rearm: toggle-font.sh and editors replace the file atomically
    onLoaded: {
      root.apply(text())
      Util.rearmWatch(this)
    }
    onFileChanged: reload()
  }
}

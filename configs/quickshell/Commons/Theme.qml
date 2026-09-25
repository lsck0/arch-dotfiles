pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// The shell's single user-facing knob file: `theme.json`, live-watched.
QtObject {
  id: root

  // Lives next to shell.qml in this checkout (symlinked to ~/.config/quickshell/theme.json by link.sh) rather than under XDG_STATE_HOME like shell.json.
  readonly property string path: Quickshell.shellDir + "/theme.json"

  // ------------------------------------------------------------------ font Family is the UI/body family only.
  property string fontFamily: "0xProto Nerd Font"
  // Base size, in px. The whole scale is derived from it.
  property int fontSize: 12

  // ------------------------------------------------- palette conditioning Defaults reproduce the hand-tuned values these knobs replaced, so an absent or empty theme.json renders exactly what the shell rendered before this file existed.

  // Forces the wallpaper's background colour into a dark band, hue and saturation kept.
  property real backgroundValueMin: 0.08
  property real backgroundValueMax: 0.26

  // WCAG contrast ratio body text is dragged to against the background.
  property real foregroundContrast: 7.0

  // Saturation/value floors that stop a washed-out wallpaper yielding a grey smudge of an accent, then the contrast ratio it is dragged to.
  property real accentMinSaturation: 0.70
  property real accentMinValue: 0.62
  property real accentContrast: 3.0

  property real urgentMinSaturation: 0.55
  property real urgentMinValue: 0.55
  property real urgentContrast: 3.0

  // Muted is the de-emphasis role; it is floored just enough to stay perceptible, NOT dragged to a legible ratio, because that would defeat its only job.
  property real mutedContrast: 1.9

  // Crossfade duration when the wallpaper (and so the palette) changes.
  property int paletteTransitionMs: 600

  // ------------------------------------------------- hacker fx (sci-fi/CRT) Neon glow, scanlines and HUD framing; all live-tunable, 0 disables each.
  property real glowStrength: 0.55      // neon bloom on accents/active elements (0..1)
  property real scanlineOpacity: 0.06   // CRT scanline overlay strength (0..0.3)
  property int  scanlineSpacing: 3       // px between scanlines
  property real phosphorBias: 0.0      // 0 = accent follows the wallpaper hue
  property bool cornerBrackets: true     // HUD corner brackets on panels/cards
  property real crtFlicker: 0.02         // subtle brightness flicker amplitude (0..0.1)
  property real matrixRain: 0.5          // digital-rain density on the background (0..1)

  // Bumped on every successful (re)load.
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
    // Floor above "unreadable", ceiling below "one widget fills the bar".
    if (font.size !== undefined) fontSize = Math.round(_num(font.size, fontSize, 6, 32))

    var p = parsed.palette || {}
    // Ordered floor-then-ceiling so a file specifying only one still yields a valid band.
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
    // A missing theme.json is the supported default state, not an error: every property above already holds the shipped value.
    printErrors: false
    // rearmWatch is load-bearing here, not defensive: toggles/toggle-font.sh writes this file atomically (jq to a temp file, then mv), and so does most editors' save.
    onLoaded: {
      root.apply(text())
      Util.rearmWatch(this)
    }
    onFileChanged: reload()
  }
}

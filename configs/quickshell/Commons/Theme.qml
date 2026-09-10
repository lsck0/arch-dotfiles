pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// The shell's single user-facing knob file: `theme.json`, live-watched.
//
// Two axes, and deliberately only two:
//
//   font    — the UI family and a base size. Everything typographic in the
//             shell (the type scale, the spacing scale, the bar grid) is
//             derived from `size` in Style.qml, so this one number rescales
//             the whole shell rather than just the body text.
//   palette — the *conditioning* knobs applied to pywal's colors.json in
//             Color.qml. There is no named-theme list here on purpose: this
//             shell has exactly one colour source (the wallpaper, via
//             pywal/wallust), and what a user actually wants to change is
//             how that source is interpreted — how dark the background is
//             forced, how much presence a washed-out accent is given, how
//             hard contrast is enforced.
//
// Everything is live: this is a FileView with watchChanges, so editing
// theme.json re-themes the running shell with no restart. Style/Color bind
// to these properties rather than reading the file themselves, so there is
// one parse and one watch for both.
//
// Every value is clamped on the way in. A theme file is hand-edited, and a
// typo that made the shell unreadable would also make it unusable to fix —
// so out-of-range input is pulled back to something legible rather than
// honoured or rejected.
QtObject {
  id: root

  // Lives next to shell.qml in this checkout (symlinked to
  // ~/.config/quickshell/theme.json by link.sh) rather than under
  // XDG_STATE_HOME like shell.json. That split is deliberate: shell.json is
  // runtime state the shell writes for itself (bar layout, plugin enablement),
  // this is tracked configuration a human edits and git records.
  readonly property string path: Quickshell.shellDir + "/theme.json"

  // ------------------------------------------------------------------ font
  //
  // Family is the UI/body family only. The icon family is pinned to a Nerd
  // Font in Style.qml and is deliberately NOT exposed here — pointing it at
  // an arbitrary family does not remove the glyphs, it silently substitutes
  // different ones (see Style.qml's font note). A theme file must not be
  // able to do that.
  property string fontFamily: "0xProto Nerd Font"
  // Base size, in px. The whole scale is derived from it.
  property int fontSize: 12

  // ------------------------------------------------- palette conditioning
  //
  // Defaults reproduce the hand-tuned values these knobs replaced, so an
  // absent or empty theme.json renders exactly what the shell rendered
  // before this file existed.

  // Forces the wallpaper's background colour into a dark band, hue and
  // saturation kept. Raise the ceiling for a lighter shell, lower the floor
  // for a blacker one.
  property real backgroundValueMin: 0.08
  property real backgroundValueMax: 0.26

  // WCAG contrast ratio body text is dragged to against the background.
  // 7.0 is AAA for normal text.
  property real foregroundContrast: 7.0

  // Saturation/value floors that stop a washed-out wallpaper yielding a grey
  // smudge of an accent, then the contrast ratio it is dragged to.
  property real accentMinSaturation: 0.45
  property real accentMinValue: 0.55
  property real accentContrast: 3.0

  property real urgentMinSaturation: 0.55
  property real urgentMinValue: 0.55
  property real urgentContrast: 3.0

  // Muted is the de-emphasis role; it is floored just enough to stay
  // perceptible, NOT dragged to a legible ratio, because that would defeat
  // its only job. Kept tunable anyway — a very low-contrast wallpaper can
  // want a nudge.
  property real mutedContrast: 1.9

  // Crossfade duration when the wallpaper (and so the palette) changes.
  // 0 disables the animation.
  property int paletteTransitionMs: 600

  // Bumped on every successful (re)load. Color.qml watches this to
  // re-condition the palette it already has in hand, so editing a knob
  // re-themes immediately instead of waiting for the next wallpaper change.
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
    // Ordered floor-then-ceiling so a file specifying only one still yields
    // a valid band.
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

    revision++
  }

  property FileView file: FileView {
    path: root.path
    watchChanges: true
    // A missing theme.json is the supported default state, not an error:
    // every property above already holds the shipped value.
    printErrors: false
    // rearmWatch is load-bearing here, not defensive: toggles/toggle-font.sh
    // writes this file atomically (jq to a temp file, then mv), and so does
    // most editors' save. Verified by hand — without it the first edit
    // applies and every later one is silently dropped.
    onLoaded: {
      root.apply(text())
      Util.rearmWatch(this)
    }
    onFileChanged: reload()
  }
}

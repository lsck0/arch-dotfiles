.pragma library

var ICONS = {
  "volume-muted": "\u{f026}",
  "volume": "\u{f028}",
  "microphone-muted": "\u{f131}",
  "microphone": "\u{f130}",
  "brightness": "\u{f042}",
  "keyboard-backlight-off": "\u{f0310}",
  "keyboard-backlight": "\u{f030c}",
  "launch": "\u{f14de}",
  "media-play": "\u{f04b}",
  "media-pause": "\u{f04c}",
  "media-next": "\u{f051}",
  "media-previous": "\u{f048}",
  "media-stop": "\u{f04d}"
}

// the progress row reserves this glyph's width, so the bar does not shift between icons
var widestIcon = ICONS["volume"]
var MAX_DEFAULT = 100
var DURATION_DEFAULT_MS = 1200

// a known name maps to its glyph, any other text is the glyph itself
function iconFor(name) {
  return ICONS[String(name || "").toLowerCase()] || name || "\u{f0e7}"
}

function integerOr(value, fallback) {
  var parsed = parseInt(value, 10)
  return isNaN(parsed) ? fallback : parsed
}

// the shown state for a present payload {icon, message, value, max, progressText, duration}; a message wins over a value
function stateFor(payload) {
  var maxValue = Math.max(1, integerOr(payload.max, MAX_DEFAULT))
  var message = String(payload.message || "")
  var parsedValue = parseInt(payload.value, 10)
  var hasProgress = !isNaN(parsedValue) && message === ""
  var value = hasProgress ? Math.max(0, Math.min(maxValue, parsedValue)) : 0
  return {
    maxValue: maxValue,
    hasProgress: hasProgress,
    value: value,
    message: message || (hasProgress ? String(payload.progressText || Math.round(value * 100 / maxValue) + "%") : ""),
    icon: iconFor(payload.icon),
    duration: Math.max(0, integerOr(payload.duration, DURATION_DEFAULT_MS))
  }
}

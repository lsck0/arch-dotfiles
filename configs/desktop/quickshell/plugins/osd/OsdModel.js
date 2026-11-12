.pragma library

var widestIcon = "\u{f028}"

var ICONS = {
  "volume-muted": "\u{f026}",
  "volume": "\u{f028}",
  "microphone-muted": "\u{f131}",
  "microphone": "\u{f130}",
  "brightness": "\u{f042}",
  "keyboard-backlight-off": "\u{f0310}",
  "keyboard-backlight": "\u{f030c}",
  "launch": "\u{f14de}"
}

// a known name maps to its glyph, any other text is the glyph itself
function iconFor(name) {
  return ICONS[String(name || "").toLowerCase()] || name || "\u{f0e7}"
}

function stateForShow(iconName, rawMessage, rawValue, rawMax, rawProgressText, rawDuration) {
  var parsedMax = parseInt(rawMax || "100", 10)
  var maxValue = isNaN(parsedMax) ? 100 : Math.max(1, parsedMax)
  var parsedValue = parseInt(rawValue || "0", 10)
  var hasProgress = rawValue !== "" && !isNaN(parsedValue) && rawMessage === ""
  var value = hasProgress ? Math.max(0, Math.min(maxValue, parsedValue)) : 0
  var percent = hasProgress ? Math.round(value * 100 / maxValue) : -1
  var parsedDuration = parseInt(rawDuration || "1200", 10)

  return {
    maxValue: maxValue,
    hasProgress: hasProgress,
    value: value,
    message: String(rawMessage || (hasProgress ? (rawProgressText || percent + "%") : "")),
    icon: iconFor(iconName),
    duration: isNaN(parsedDuration) ? 1200 : Math.max(0, parsedDuration)
  }
}

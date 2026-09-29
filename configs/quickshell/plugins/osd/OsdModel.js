.pragma library

function clamp(value, min, max) {
  return Math.max(min, Math.min(max, value))
}

// widest glyph, keeps the icon column from jittering
var widestIcon = ""

function iconFor(name, percent) {
  var n = String(name || "").toLowerCase()
  if (n === "volume-muted" || n === "volume-mute" || n === "muted" || n === "mute") return ""
  if (n === "volume-low") return ""
  if (n === "volume-medium" || n === "volume-high" || n === "volume") return ""
  if (n === "microphone-muted" || n === "microphone-off" || n === "mic-muted" || n === "mic-off") return ""
  if (n === "microphone" || n === "mic") return ""
  if (n === "brightness" || n === "display") return ""
  // md-keyboard / md-keyboard_off
  if (n === "keyboard-backlight-off" || n === "kbd-backlight-off") return "\u{f0310}"
  if (n === "keyboard-backlight" || n === "kbd-backlight" || n === "keyboard") return "\u{f030c}"
  if (n.length > 0) return name
  if (percent <= 33) return ""
  if (percent <= 66) return ""
  return ""
}

function stateForShow(iconName, rawMessage, rawValue, rawMax, rawProgressText, rawDuration) {
  var maxValue = Math.max(1, parseInt(rawMax || "100", 10))
  var parsedValue = parseInt(rawValue || "0", 10)
  var hasProgress = rawValue !== "" && !isNaN(parsedValue) && rawMessage === ""
  var value = hasProgress ? clamp(parsedValue, 0, maxValue) : 0
  var percent = hasProgress ? Math.round(value * 100 / maxValue) : -1
  var parsedDuration = parseInt(rawDuration || "1200", 10)

  return {
    maxValue: maxValue,
    hasProgress: hasProgress,
    value: value,
    message: String(rawMessage || (hasProgress ? (rawProgressText || percent + "%") : "")),
    icon: iconFor(iconName, percent),
    duration: isNaN(parsedDuration) ? 1200 : Math.max(0, parsedDuration)
  }
}

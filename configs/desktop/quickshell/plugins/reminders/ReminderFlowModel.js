.pragma library

// the reminder grammar the overlay and the launcher share; capture.nu's minutes-of and clock-next read the same words
var UNIT = "(?:m|min|mins|minutes)"
var DURATION = new RegExp("^(?:(\\d+)h)?(?:(\\d+)" + UNIT + "?)?$", "i")
var UNIT_WORD = new RegExp("^" + UNIT + "$", "i")
var CLOCK = /^([01]?\d|2[0-3]):([0-5]\d)$/

function validMinutes(value) {
  var minutes = String(value || "").trim()
  return /^[0-9]+$/.test(minutes) && Number(minutes) > 0 ? minutes : ""
}

// 90, 10m, 10min, 2h, 1h30m: whole minutes, 0 when it is not a duration
function minutesOf(word) {
  var match = DURATION.exec(String(word || ""))
  return match ? Number(match[1] || 0) * 60 + Number(match[2] || 0) : 0
}

// 15:00, 9:05: the next time the clock reads it after now (today, else tomorrow), null when it is not a clock time
function clockNext(word, now) {
  var match = CLOCK.exec(String(word || ""))
  if (!match) return null
  var at = new Date(now.getFullYear(), now.getMonth(), now.getDate(), Number(match[1]), Number(match[2]), 0, 0)
  if (at.getTime() <= now.getTime()) at.setDate(at.getDate() + 1)
  return at
}

// the duration as the first word, then the name; "10 min tea" with the unit apart still reads as 10 minutes
function parseEntry(text) {
  var words = String(text || "").trim().split(/\s+/)
  if (words.length > 1 && /^[0-9]+$/.test(words[0]) && UNIT_WORD.test(words[1])) words.splice(0, 2, words[0] + words[1])
  var minutes = minutesOf(words[0])
  if (minutes <= 0) return null
  return { minutes: String(minutes), name: words.slice(1).join(" ") }
}

// end of flags before the name: a name such as "--call mom" stays the name
function reminderArgs(minutes, name) {
  var valid = validMinutes(minutes)
  if (!valid) return []

  var args = [valid]
  var text = String(name || "").trim()
  if (text.length > 0) args.push("--", text)
  return args
}

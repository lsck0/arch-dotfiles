.pragma library

function validMinutes(value) {
  var minutes = String(value || "").trim()
  return /^[0-9]+$/.test(minutes) && Number(minutes) > 0 ? minutes : ""
}

function parseEntry(text) {
  var match = /^\s*([0-9]+)\s*(?:m|min|mins|minutes)?(?:\s+(.*))?$/i.exec(String(text || ""))
  if (!match || !validMinutes(match[1])) return null
  return { minutes: match[1], name: String(match[2] || "").trim() }
}

function reminderArgs(minutes, name) {
  var valid = validMinutes(minutes)
  if (!valid) return []

  var args = [valid]
  var text = String(name || "").trim()
  if (text.length > 0) args.push(text)
  return args
}

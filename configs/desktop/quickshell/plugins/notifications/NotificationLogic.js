.pragma library

// NotificationUrgency values, the enum is not reachable from a .pragma library
var URGENCY_NORMAL = 1
var URGENCY_CRITICAL = 2

function isChromiumDerived(app, appIcon) {
  return /chrom|brave|vivaldi|microsoft-edge|opera/.test((String(app || "") + "\n" + String(appIcon || "")).toLowerCase())
}

// qt reads the first alnum run after "<" as the tag name and closes an unterminated trailing tag itself
function stripImageTags(text) {
  return text.replace(/<[^A-Za-z0-9>]*img(?![A-Za-z0-9])[^>]*(?:>|$)/gi, "")
}

function styledBody(body, app, appIcon) {
  return sanitizeBody(body, app, appIcon).replace(/\r\n|\r|\n/g, "<br/>")
}

function sanitizeBody(body, app, appIcon) {
  var text = stripImageTags(String(body || ""))
  if (!isChromiumDerived(app, appIcon)) return text

  return text
    .replace(/^\s*<a\b[^>]*>\s*(?:https?:\/\/|www\.)?(?:[a-z0-9-]+\.)+[a-z]{2,}(?::\d+)?(?:\/[^<\s]*)?\s*<\/a>\s*/i, "")
    .replace(/^\s*(?:https?:\/\/|www\.)?(?:[a-z0-9-]+\.)+[a-z]{2,}(?::\d+)?(?:\/\S*)?\s+/i, "")
}

function summaryStartsWithGlyph(summary) {
  return /^\s*(?:[\uD800-\uDBFF][\uDC00-\uDFFF]|\S) {2}/.test(String(summary || ""))
}

var ACTION_APP = "quickshell-action"

function shouldBypassDnd(notification) {
  var appName = String((notification && notification.appName) || "")
  return appName === ACTION_APP || (appName === "notify-send" && notification.urgency === URGENCY_CRITICAL)
}

function isEphemeralApp(appName) {
  return appName === "notify-send" || appName === ACTION_APP
}

function stringHint(hints, name) {
  try {
    var value = hints ? hints[name] : undefined
    if (value !== undefined && value !== null) return String(value)
  } catch (e) {
  }
  return ""
}

// any d-bus client sets this hint: only ntfy-notify.nu's shape (xdg-open on an https link) runs
function parseExecArgv(value) {
  var parsed
  try {
    parsed = JSON.parse(String(value || ""))
  } catch (e) {
    return null
  }
  if (!Array.isArray(parsed) || parsed.length !== 2 || parsed[0] !== "xdg-open") return null
  if (typeof parsed[1] !== "string" || !/^https:\/\/[^\s\x00-\x1f\x7f]+$/.test(parsed[1])) return null
  return parsed
}

function nonNegative(value) {
  var n = Number(value || 0)
  return isFinite(n) && n > 0 ? n : 0
}

function snapshotOf(notification, timestamp, entryName) {
  var n = notification || {}
  var id = n.id || 0
  return {
    id: id,
    originalId: id,
    app: n.appName || entryName || n.desktopEntry || "",
    appIcon: n.appIcon || "",
    summary: String(n.summary || ""),
    body: n.body || "",
    image: n.image || "",
    glyph: stringHint(n.hints, "omarchy-glyph"),
    execArgv: stringHint(n.hints, "omarchy-exec-argv"),
    urgency: n.urgency,
    expireTimeout: nonNegative(n.expireTimeout),
    timestamp: timestamp
  }
}

var HIDDEN_ACTION_IDS = ["mail-mark-read", "mark", "mark-read", "mark_read"]

function isHiddenAction(identifier, text) {
  var id = String(identifier || "").toLowerCase()
  return HIDDEN_ACTION_IDS.indexOf(id) >= 0 || /^\s*mark (?:as )?read\s*$/i.test(String(text || ""))
}

var POPUP_ROLES = ["app", "appIcon", "summary", "body", "image", "glyph", "execArgv", "urgency", "expireTimeout"]

function popupRowChanged(row, updated) {
  return POPUP_ROLES.some(function(role) { return row[role] !== updated[role] })
}

function replacementSnapshot(notification, originalId, timestamp, entryName) {
  var updated = snapshotOf(notification, timestamp, entryName)
  updated.id = originalId
  updated.originalId = originalId
  return updated
}

function historyEntry(value) {
  var e = value || {}
  return {
    id: e.id || 0,
    originalId: e.originalId || e.id || 0,
    app: e.app || "",
    appIcon: e.appIcon || "",
    summary: e.summary || "",
    body: e.body || "",
    image: e.image || "",
    glyph: e.glyph || "",
    execArgv: e.execArgv || "",
    urgency: typeof e.urgency === "number" ? e.urgency : URGENCY_NORMAL,
    expireTimeout: 0,
    timestamp: e.timestamp || 0
  }
}

function popupEntry(value) {
  var entry = historyEntry(value)
  entry.expireTimeout = nonNegative((value || {}).expireTimeout)
  var deadline = nonNegative((value || {}).deadline)
  if (deadline > 0) entry.deadline = deadline
  return entry
}

function imageStem(entry) {
  var e = entry || {}
  return String(e.timestamp || 0) + "-" + String(e.originalId || 0)
}

function popupFileName(entry) {
  return imageStem(entry) + ".json"
}

var PERSISTED_IMAGE_ROLES = ["appIcon", "image"]

function localImageFile(value) {
  var s = String(value || "")
  if (s.indexOf("file://") === 0) {
    s = s.slice(7)
    try { s = decodeURIComponent(s) } catch (e) {}
  }
  return s.charAt(0) === "/" ? s : ""
}

function persistablePopup(entry, imagesDir) {
  var out = Object.assign({}, entry)
  var copies = []
  for (var i = 0; i < PERSISTED_IMAGE_ROLES.length; i++) {
    var role = PERSISTED_IMAGE_ROLES[i]
    var value = String(out[role] || "")
    if (!value) continue
    var source = localImageFile(value)
    if (source) {
      var copy = String(imagesDir || "") + imageStem(out) + "-" + role
      if (source !== copy) copies.push({ from: source, to: copy })
      out[role] = "file://" + copy
    } else if (value.indexOf("image://") === 0) {
      out[role] = ""
    }
  }
  return { entry: out, copies: copies }
}

// single line: restore parses files line by line
function serializePopup(entry) {
  return JSON.stringify(popupEntry(entry))
}

function parsePopupFiles(raw) {
  var entries = []
  String(raw || "").split("\n").forEach(function(line) {
    if (!line.trim()) return
    try {
      var value = JSON.parse(line)
      if (value && typeof value === "object") entries.push(popupEntry(value))
    } catch (e) {
    }
  })
  return entries.sort(function(a, b) { return b.timestamp - a.timestamp })
}

function popupExpired(entry, duration, now) {
  if (entry.deadline) return now >= entry.deadline
  return duration > 0 && now - entry.timestamp >= duration
}

function historyRows(raw, liveRows, limit) {
  var out = []
  var seen = {}
  liveRows.concat(parsePopupFiles(raw)).forEach(function(entry) {
    var key = popupFileName(entry)
    if (seen[key]) return
    seen[key] = true
    out.push(historyEntry(entry))
  })
  return out.sort(function(a, b) { return b.timestamp - a.timestamp }).slice(0, limit)
}

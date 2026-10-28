.pragma library

var URGENCY_NORMAL = 1
var URGENCY_CRITICAL = 2

function isChromiumDerived(app, appIcon) {
  return /chrom|brave|vivaldi|microsoft-edge|opera/.test((String(app || "") + "\n" + String(appIcon || "")).toLowerCase())
}

// until stable: one pass would let a nested tag rebuild an <img> that StyledText then fetches
function stripImageTags(text) {
  var prev
  do {
    prev = text
    text = text.replace(/<[^A-Za-z0-9>]*img(?![A-Za-z0-9])[^>]*(?:>|$)/gi, "")
  } while (text !== prev)
  return text
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

var DEFAULT_APP_NAMES = ["notify-send"]

function legacyIcon(icon) {
  return String(icon || "").replace(/^gtk-dialog-(info|warning|error|question)$/, "dialog-$1")
}

function snapshotOf(notification, timestamp, entryName, entryIcon) {
  var n = notification || {}
  var id = n.id || 0
  var named = n.appName && DEFAULT_APP_NAMES.indexOf(n.appName) < 0 ? n.appName : ""
  return {
    id: id,
    originalId: id,
    app: named || entryName || n.desktopEntry || n.appName || "",
    appIcon: legacyIcon(n.appIcon) || entryIcon || "",
    summary: String(n.summary || ""),
    body: n.body || "",
    image: n.image || "",
    glyph: stringHint(n.hints, "lsck0-glyph"),
    execArgv: stringHint(n.hints, "lsck0-exec-argv"),
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

function replacementSnapshot(notification, originalId, timestamp, entryName, entryIcon) {
  var updated = snapshotOf(notification, timestamp, entryName, entryIcon)
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

// The bar's history list from the popup and history files' lines: one entry per notification, newest first.
function historyList(raw) {
  var seen = {}
  var rows = []
  String(raw || "").split("\n").forEach(function(line) {
    var entry = null
    try { entry = JSON.parse(line) } catch (e) { return }
    if (!entry || typeof entry !== "object" || Array.isArray(entry)) return
    var key = entry.timestamp + ":" + entry.originalId
    if (seen[key]) return
    seen[key] = true
    rows.push(entry)
  })
  return rows.sort(function(a, b) { return (b.timestamp || 0) - (a.timestamp || 0) })
}

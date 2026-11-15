.pragma library

// addedMs is the wall-clock time an entry entered the history; expireEntries drops by it
function stamped(entry, value) {
  var addedMs = Number(value.addedMs)
  if (addedMs > 0) entry.addedMs = addedMs
  return entry
}

function normalizeEntry(value) {
  if (typeof value === "string")
    return value.trim().length > 0 ? { type: "text", text: value } : null

  if (!value || typeof value !== "object") return null

  var type = String(value.type || value.kind || "")
  if (type === "text") {
    var text = String(value.text || "")
    return text.trim().length > 0 ? stamped({ type: "text", text: text }, value) : null
  }

  if (type === "image") {
    var path = String(value.path || "")
    if (!path) return null
    var entry = {
      type: "image",
      path: path,
      mime: String(value.mime || "image/png")
    }
    if (value.capturedAt !== undefined && value.capturedAt !== null)
      entry.capturedAt = String(value.capturedAt)
    return stamped(entry, value)
  }

  return null
}

function entryKey(entry) {
  if (!entry) return ""
  if (entry.type === "image") return "image:" + String(entry.path || "")
  return "text:" + String(entry.text || "")
}

function parseHistory(raw) {
  try {
    var parsed = JSON.parse(String(raw || "[]"))
    var next = []
    if (!Array.isArray(parsed)) return next

    for (var i = 0; i < parsed.length; i++) {
      var entry = normalizeEntry(parsed[i])
      if (entry) next.push(entry)
    }
    return next
  } catch (e) {
    return []
  }
}

// An entry saved without a stamp counts from nowMs, so it expires too; true when one was stamped.
function stampUnstamped(history, nowMs) {
  var unstamped = history.filter(function (entry) { return entry.addedMs === undefined })
  unstamped.forEach(function (entry) { entry.addedMs = nowMs })
  return unstamped.length > 0
}

function expireEntries(history, nowMs, maxAgeMs) {
  return history.filter(function (entry) { return nowMs - entry.addedMs < maxAgeMs })
}

// Milliseconds until the oldest entry expires, -1 for an empty history.
function expiryDueMs(history, nowMs, maxAgeMs) {
  if (history.length === 0) return -1
  var oldestMs = history.reduce(function (min, entry) { return Math.min(min, entry.addedMs) }, Infinity)
  return Math.max(0, oldestMs + maxAgeMs - nowMs)
}

function addEntry(history, entry, limit, nowMs) {
  var normalized = normalizeEntry(entry)
  if (!normalized) return history.slice(0, limit)
  normalized.addedMs = nowMs

  var key = entryKey(normalized)
  var next = [normalized]

  for (var i = 0; i < history.length && next.length < limit; i++) {
    var existing = normalizeEntry(history[i])
    if (!existing || entryKey(existing) === key) continue
    next.push(existing)
  }

  return next
}

function removeEntryAt(history, index) {
  var next = history.slice()
  if (index >= 0 && index < next.length) next.splice(index, 1)
  return next
}

function parseEntryJson(line) {
  var raw = String(line || "").trim()
  if (!raw) return null
  try { return normalizeEntry(JSON.parse(raw)) } catch (e) { return null }
}

function searchableText(entry) {
  if (!entry) return ""
  if (entry.type === "image") return "image " + String(entry.mime || "") + " " + String(entry.capturedAt || "")
  return String(entry.text || "") + " " + fileEntryText(entry)
}

function decodeFileUri(uri) {
  var value = String(uri || "").trim()
  if (value.indexOf("file://") !== 0) return ""

  var path = value.substring(7)
  if (path.indexOf("localhost/") === 0) path = path.substring(9)
  if (path.charAt(0) !== "/") return ""

  try { return decodeURIComponent(path) } catch (e) { return path }
}

function filePaths(entry) {
  if (!entry || entry.type !== "text") return []

  // a file entry is a uri-list: every line a file URI, blank lines and # comments aside; one URI inside other text
  // keeps the entry text, so picking it pastes the whole text back
  var lines = String(entry.text || "").split(/\r?\n/)
  var paths = []
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i].trim()
    if (line === "" || line.charAt(0) === "#") continue
    var path = decodeFileUri(line)
    if (!path) return []
    paths.push(path)
  }
  return paths
}

function fileName(path) {
  return String(path || "").split("/").pop()
}

function isImagePath(path) {
  return /\.(png|jpe?g|webp|gif|bmp|tiff?)$/i.test(String(path || ""))
}

function fileEntryText(entry) {
  var paths = filePaths(entry)
  if (paths.length === 0) return ""
  if (paths.length === 1) return fileName(paths[0])
  return paths.length + " files"
}

function previewText(entry) {
  if (!entry) return ""
  if (entry.type === "image") return entry.capturedAt ? "Image from " + entry.capturedAt : "Image"
  var fileText = fileEntryText(entry)
  if (fileText) return fileText
  return String(entry.text || "").replace(/\s+/g, " ")
}

// a file entry goes back on the clipboard as the uri-list it came as, one CRLF-terminated URI per line
function uriListText(entry) {
  var lines = String(entry && entry.text || "").split(/\r?\n/)
  var uris = []
  for (var i = 0; i < lines.length; i++) {
    if (decodeFileUri(lines[i])) uris.push(lines[i].trim())
  }
  return uris.length > 0 ? uris.join("\r\n") + "\r\n" : ""
}

function fullText(entry) {
  if (!entry) return ""
  var paths = filePaths(entry)
  if (paths.length > 0) return paths.join("\n")
  return String(entry.text || "")
}

var displayTextLimit = 8192

function cappedEntry(entry) {
  if (!entry || entry.type !== "text" || entry.text.length <= displayTextLimit) return entry

  var cut = entry.text.lastIndexOf("\n", displayTextLimit)
  return { type: "text", text: entry.text.slice(0, cut > 0 ? cut : displayTextLimit) }
}

function displayRows(history, query, limit) {
  var needle = String(query || "").trim().toLowerCase()
  var rows = []

  for (var i = 0; i < history.length; i++) {
    var whole = normalizeEntry(history[i])
    if (!whole) continue
    if (needle && searchableText(whole).toLowerCase().indexOf(needle) < 0) continue
    var entry = cappedEntry(whole)

    var paths = filePaths(entry)
    var isFile = paths.length > 0
    var isImage = entry.type === "image"
    var previewPath = isImage ? String(entry.path || "") : (isFile && paths.length === 1 && isImagePath(paths[0]) ? paths[0] : "")
    rows.push({
      entryType: isFile ? "file" : entry.type,
      fullText: isImage ? "" : fullText(whole),
      copyText: isImage ? "" : (isFile ? uriListText(whole) : String(whole.text || "")),
      paneText: isImage ? "" : fullText(entry),
      previewText: previewText(entry),
      previewImage: previewPath,
      path: isImage ? String(entry.path || "") : (isFile && paths.length === 1 ? paths[0] : ""),
      mime: isImage ? String(entry.mime || "image/png") : (isFile ? "text/uri-list" : "text/plain"),
      index: i
    })
    if (rows.length >= limit) break
  }

  return rows
}

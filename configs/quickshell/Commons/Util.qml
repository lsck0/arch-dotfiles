pragma Singleton
import Quickshell
import QtQuick

// Trimmed from omarchy-shell's Util.qml: kept the pure helpers actually used by the widgets in this repo's bar.
QtObject {
  id: root

  function clamp(value, min, max) {
    var n = Number(value)
    if (!isFinite(n)) return min
    return Math.max(min, Math.min(max, n))
  }

  function clampAlpha(value) {
    return clamp(value, 0, 1)
  }

  // file:// URL with each path segment percent-encoded so spaces and special chars in user paths don't break Image.source.
  function fileUrl(path) {
    if (!path) return ""
    return "file://" + String(path).split("/").map(encodeURIComponent).join("/")
  }

  function alpha(c, opacity) {
    var a = clampAlpha(opacity)
    if (!c) return Qt.rgba(0, 0, 0, a)
    if (typeof c === "string") c = Qt.color(c)
    return Qt.rgba(c.r, c.g, c.b, a)
  }

  // Single-quote a string for bash.
  function shellQuote(value) {
    return "'" + String(value || "").replace(/'/g, "'\\''") + "'"
  }

  function execDetached(command) {
    Quickshell.execDetached(["bash", "-lc", command])
  }

  // Added for the quickshell Phase 2 plugin-registry port — PluginRegistry.qml/
  // shell.qml/AppLibrary.qml need these; ported verbatim from upstream, no
  // shell.json coupling in any of the four.
  function isPlainObject(value) {
    return value !== null && typeof value === "object" && !Array.isArray(value)
  }

  // IDENTITY FUNCTION — it does not canonicalize anything, despite the name.
  function canonicalWidgetId(id) {
    return String(id || "")
  }

  // Best-effort base64 decode.
  function decodeBase64(value) {
    var s = String(value || "")
    if (!s) return ""
    try { return Qt.atob(s) } catch (e) { return "" }
  }

  function cloneJson(value) {
    return JSON.parse(JSON.stringify(value === undefined ? null : value))
  }

  // Re-arm a FileView's change watch.
  function rearmWatch(view) {
    if (!view) return
    Qt.callLater(function () {
      view.watchChanges = false
      view.watchChanges = true
    })
  }

  // Copy-on-write helpers for `property var` maps.
  function mapSet(map, key, value) {
    var next = ({})
    for (var k in map) next[k] = map[k]
    next[String(key)] = value
    return next
  }

  function mapRemove(map, key) {
    var target = String(key)
    var next = ({})
    for (var k in map) if (k !== target) next[k] = map[k]
    return next
  }
}

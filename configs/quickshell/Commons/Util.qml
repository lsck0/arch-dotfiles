pragma Singleton
import Quickshell
import QtQuick

// Trimmed from omarchy-shell's Util.qml: kept the pure helpers actually used
// by the widgets in this repo's bar. No shell.json layout-normalization or
// waybar-style JSON parsing — this bar has no dynamic layout config.
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

  // file:// URL with each path segment percent-encoded so spaces and
  // special chars in user paths don't break Image.source.
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

  // Single-quote a string for bash. The replace handles embedded single
  // quotes by closing, escaping, and re-opening the literal.
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
  // Upstream stripped a distro prefix from widget ids here; this repo has no
  // prefix to strip, so the body collapsed to a String() coercion. Kept
  // (rather than inlined into its ~17 call sites, most of which read
  // `Util.canonicalWidgetId(String(x))` and are therefore doubly redundant)
  // because those call sites live in PluginRegistry.qml, which is deliberately
  // a close port of upstream and easier to re-sync if its shape is preserved.
  // If that ever stops being worth it, this is a mechanical sweep to remove.
  function canonicalWidgetId(id) {
    return String(id || "")
  }

  // Best-effort base64 decode. Returns "" on parse failure rather than
  // surfacing garbage downstream.
  function decodeBase64(value) {
    var s = String(value || "")
    if (!s) return ""
    try { return Qt.atob(s) } catch (e) { return "" }
  }

  function cloneJson(value) {
    return JSON.parse(JSON.stringify(value === undefined ? null : value))
  }

  // Re-arm a FileView's change watch.
  //
  // FileView watches an inode, not a path, and does not re-establish itself
  // when that inode is replaced. An atomic write (temp file + rename) does
  // exactly that, so after one such write the watch is left on the unlinked
  // inode and every later change is silently ignored — the feature looks
  // flaky rather than broken, which is the worst way for it to fail.
  //
  // Call from onLoaded. Deferred so the toggle runs after the load that
  // triggered it, not inside its own signal handler.
  function rearmWatch(view) {
    if (!view) return
    Qt.callLater(function () {
      view.watchChanges = false
      view.watchChanges = true
    })
  }

  // Copy-on-write helpers for `property var` maps.
  //
  // QML does not emit a change signal when a var-typed object is mutated in
  // place, so every binding on it goes stale silently — the only way to
  // publish an update is to assign a *new* object. shell.qml carried six
  // hand-written copies of this loop (openPanelIds, pendingPayloads,
  // panelLoaders, _services twice, pluginWidgetComponents), which is six
  // places to get the reassign wrong rather than one.
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

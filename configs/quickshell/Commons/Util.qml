pragma Singleton
import Quickshell
import QtQuick

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

  // percent-encode segments so odd paths survive Image.source
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

  function shellQuote(value) {
    return "'" + String(value || "").replace(/'/g, "'\\''") + "'"
  }

  function execDetached(command) {
    Quickshell.execDetached(["bash", "-lc", command])
  }

  function isPlainObject(value) {
    return value !== null && typeof value === "object" && !Array.isArray(value)
  }

  function cloneJson(value) {
    return JSON.parse(JSON.stringify(value === undefined ? null : value))
  }

  function rearmWatch(view) {
    if (!view) return
    Qt.callLater(function () {
      view.watchChanges = false
      view.watchChanges = true
    })
  }

  // copy-on-write so property var maps notify
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

  // sparkline window, one sample per poll
  readonly property int historyCountMax: 60

  // copy-on-write append that keeps the newest historyCountMax samples
  function historyPush(history, value) {
    var next = (history || []).slice()
    next.push(value)
    if (next.length > historyCountMax) next.shift()
    return next
  }
}

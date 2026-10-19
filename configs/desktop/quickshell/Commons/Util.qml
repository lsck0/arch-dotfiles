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

  function isPlainObject(value) {
    return value !== null && typeof value === "object" && !Array.isArray(value)
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
    for (let k in map) next[k] = map[k]
    next[String(key)] = value
    return next
  }

  function clock(seconds) {
    var total = isFinite(seconds) ? Math.max(0, Math.floor(seconds)) : 0
    var h = Math.floor(total / 3600)
    var m = Math.floor(total % 3600 / 60)
    var ss = String(total % 60).padStart(2, "0")
    return h > 0 ? h + ":" + String(m).padStart(2, "0") + ":" + ss : m + ":" + ss
  }

  function span(minutes) {
    var m = Math.max(0, Math.round(Number(minutes) || 0))
    if (m < 60) return m + "m"
    if (m < 2880) return Math.floor(m / 60) + "h"
    return Math.floor(m / 1440) + "d"
  }

  function ago(minutes) { return span(minutes) + " ago" }

  readonly property string timeFormat: Qt.locale().timeFormat(Locale.ShortFormat)
  readonly property string dayFormat: Qt.locale().dateFormat(Locale.ShortFormat).replace(/\W*y+\W*/, "")

  readonly property var byteUnits: ["B", "KB", "MB", "GB", "TB"]

  function bytes(count) {
    var v = Math.max(0, Number(count) || 0)
    var i = 0
    while (v >= 1024 && i < byteUnits.length - 1) { v /= 1024; i++ }
    return Number(v.toPrecision(3)) + " " + byteUnits[i]
  }

  function level(value, thresholds) {
    var stops = Colors.rampStops
    if (value >= thresholds[2]) return Colors.ramp(stops[3])
    if (value >= thresholds[1]) return Colors.ramp(stops[2])
    if (value >= thresholds[0]) return Colors.ramp(stops[1])
    return Colors.ramp(stops[0])
  }

  function iconSource(icon) {
    var value = String(icon || "")
    if (value.length === 0) return ""
    if (value.indexOf("file://") === 0 || value.indexOf("image://") === 0) return value
    if (value.charAt(0) === "/") return fileUrl(value)
    return Quickshell.iconPath(value, true)
  }

  function isWordDelete(key, modifiers) {
    return (modifiers & Qt.ControlModifier) !== 0 && (key === Qt.Key_W || key === Qt.Key_Backspace)
  }

  function wordStart(text, position) {
    var s = String(text || "")
    var i = Math.max(0, Math.min(position, s.length))
    while (i > 0 && /\s/.test(s.charAt(i - 1))) i--
    var word = i > 0 && /\w/.test(s.charAt(i - 1))
    while (i > 0 && !/\s/.test(s.charAt(i - 1)) && /\w/.test(s.charAt(i - 1)) === word) i--
    return i
  }

  function wordDelete(text) {
    var s = String(text || "")
    return s.slice(0, wordStart(s, s.length))
  }

  function completion(prefix, candidates) {
    var hits = (candidates || []).filter(function (c) { return String(c).indexOf(prefix) === 0 })
    if (hits.length === 0) return prefix
    var out = String(hits[0])
    for (let i = 1; i < hits.length; i++) {
      let c = String(hits[i])
      let n = 0
      while (n < out.length && n < c.length && out.charAt(n) === c.charAt(n)) n++
      out = out.slice(0, n)
    }
    return out
  }

  readonly property int historyCountMax: 60

  function historyPush(history, value) {
    var next = (history || []).slice()
    next.push(value)
    if (next.length > historyCountMax) next.shift()
    return next
  }
}

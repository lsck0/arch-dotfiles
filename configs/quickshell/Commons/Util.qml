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

  // "m:ss", "h:mm:ss" from an hour on
  function clock(seconds) {
    var total = isFinite(seconds) ? Math.max(0, Math.floor(seconds)) : 0
    var h = Math.floor(total / 3600)
    var m = Math.floor(total % 3600 / 60)
    var ss = String(total % 60).padStart(2, "0")
    return h > 0 ? h + ":" + String(m).padStart(2, "0") + ":" + ss : m + ":" + ss
  }

  // minutes as "5m", "47h", "3d"; days only past two so "36h" stays exact
  function span(minutes) {
    var m = Math.max(0, Math.round(Number(minutes) || 0))
    if (m < 60) return m + "m"
    if (m < 2880) return Math.floor(m / 60) + "h"
    return Math.floor(m / 1440) + "d"
  }

  function ago(minutes) { return span(minutes) + " ago" }

  readonly property var byteUnits: ["B", "KB", "MB", "GB", "TB"]

  // binary units at three significant digits: "512 B", "1.5 MB", "523 MB"; rates append "/s"
  function bytes(count) {
    var v = Math.max(0, Number(count) || 0)
    var i = 0
    while (v >= 1024 && i < byteUnits.length - 1) { v /= 1024; i++ }
    return Number(v.toPrecision(3)) + " " + byteUnits[i]
  }

  // severity color for a higher-is-worse value against ascending [warn, high, critical]
  function level(value, thresholds) {
    if (value >= thresholds[2]) return Color.semantic.live
    if (value >= thresholds[1]) return Color.semantic.recording
    if (value >= thresholds[0]) return Color.semantic.warn
    return Color.accent
  }

  // image source for a freedesktop icon name, path or url; "" when there is none
  function iconSource(icon) {
    var value = String(icon || "")
    if (value.length === 0) return ""
    if (value.indexOf("file://") === 0 || value.indexOf("image://") === 0) return value
    if (value.charAt(0) === "/") return fileUrl(value)
    return Quickshell.iconPath(value, true)
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

pragma Singleton
import Quickshell
import Quickshell.Hyprland
import QtQuick

QtObject {
  function fileUrl(path) {
    if (!path) return ""
    return "file://" + String(path).split("/").map(encodeURIComponent).join("/")
  }

  // a non-numeric opacity reads as 0
  function alpha(c, opacity) {
    var a = isFinite(Number(opacity)) ? Math.max(0, Math.min(1, Number(opacity))) : 0
    if (!c) return Qt.rgba(0, 0, 0, a)
    if (typeof c === "string") c = Qt.color(c)
    return Qt.rgba(c.r, c.g, c.b, a)
  }

  function shellQuote(value) {
    return "'" + String(value || "").replace(/'/g, "'\\''") + "'"
  }

  // a list, also one that crossed a var signal or property: QML hands that over as a sequence, for which
  // Array.isArray is false
  function isList(value) {
    return Array.isArray(value)
      || (value !== null && typeof value === "object" && typeof value.length === "number" && typeof value.map === "function")
  }

  function isPlainObject(value) {
    return value !== null && typeof value === "object" && !isList(value)
  }

  // a JSON object from text, {} for empty, invalid or non-object text
  function parseObject(text) {
    var parsed
    try { parsed = JSON.parse(String(text || "").trim() || "{}") } catch (e) { return ({}) }
    return isPlainObject(parsed) ? parsed : ({})
  }

  function rearmWatch(view) {
    if (!view) return
    Qt.callLater(function () {
      view.watchChanges = false
      view.watchChanges = true
    })
  }

  function mapSet(map, key, value) {
    var next = Object.assign({}, map)
    next[String(key)] = value
    return next
  }

  function mapWithout(map, key) {
    var next = Object.assign({}, map)
    delete next[String(key)]
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

  // a count with its noun: 1 reminder, 2 reminders
  function count(n, noun) { return n + " " + noun + (Number(n) === 1 ? "" : "s") }

  readonly property real bytesPerMib: 1024 * 1024
  readonly property real bytesPerGib: bytesPerMib * 1024
  readonly property var byteSuffixes: ["B", "K", "M", "G", "T"]
  readonly property int byteSuffixDecimalsFrom: 3
  // below this a smaller unit keeps its decimal too (1.5M, not 2M)
  readonly property int byteWholeFrom: 10

  function byteExponent(bytes) {
    var exponent = 0
    for (let v = Math.max(0, Number(bytes) || 0); v >= 1024 && exponent < byteSuffixes.length - 1; v /= 1024) exponent++
    return exponent
  }

  // the shell's one size form: binary units under the one-letter suffix free -h and the lock screen use (340K, 29.5G)
  function bytes(bytes) {
    var exponent = byteExponent(bytes)
    var v = Math.max(0, Number(bytes) || 0) / Math.pow(1024, exponent)
    var decimal = exponent >= byteSuffixDecimalsFrom || (exponent > 0 && v < byteWholeFrom)
    return (decimal ? v.toFixed(1) : Math.round(v)) + byteSuffixes[exponent]
  }

  // used of total in the total's unit: 29.5/60G
  function bytesOf(used, total) {
    var exponent = byteExponent(total)
    var unit = Math.pow(1024, exponent)
    return (Math.max(0, Number(used) || 0) / unit).toFixed(1) + "/" + (Math.max(0, Number(total) || 0) / unit).toFixed(0) + byteSuffixes[exponent]
  }

  readonly property string timeFormat: Qt.locale().timeFormat(Locale.ShortFormat)
  readonly property string dayFormat: Qt.locale().dateFormat(Locale.ShortFormat).replace(/\W*y+\W*/, "")

  function level(value, thresholds) {
    var stops = Colors.rampStops
    if (value >= thresholds[2]) return Colors.ramp(stops[3])
    if (value >= thresholds[1]) return Colors.ramp(stops[2])
    if (value >= thresholds[0]) return Colors.ramp(stops[1])
    return Colors.ramp(stops[0])
  }

  function screenNamed(name) {
    return Array.from(Quickshell.screens).find(function (s) { return String(s.name) === String(name) }) || null
  }

  function focusedScreen() {
    return screenNamed(Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : "")
  }

  function iconSource(icon) {
    var value = String(icon || "")
    if (value.length === 0) return ""
    if (value.indexOf("file://") === 0 || value.indexOf("image://") === 0) return value
    if (value.charAt(0) === "/") return fileUrl(value)
    return Quickshell.iconPath(value, true)
  }

  // a low toast as the app the shell shows through dnd (NotificationLogic.js ACTION_APP); shell.nu's action-notify in nu
  function actionNotify(glyph, title, body) {
    Quickshell.execDetached(["notify-send", "-a", "quickshell-action", "-u", "low"]
      .concat(glyph ? ["-h", "string:lsck0-glyph:" + glyph] : [], ["--", title, body]))
  }

  // a key event's text that types one visible character
  function printable(text) { return !!text && text.length === 1 && text.charCodeAt(0) >= 32 && text.charCodeAt(0) !== 127 }

  // the readline and vim chords a list takes beside the arrows: Ctrl+N or Ctrl+J down, Ctrl+P or Ctrl+K up
  function isNext(key, modifiers) { return (modifiers & Qt.ControlModifier) !== 0 && (key === Qt.Key_N || key === Qt.Key_J) }
  function isPrev(key, modifiers) { return (modifiers & Qt.ControlModifier) !== 0 && (key === Qt.Key_P || key === Qt.Key_K) }

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

pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Services.Pipewire

Singleton {
  id: root

  readonly property string eqName: "eq"
  readonly property string peakMonitorName: "quickshell"
  readonly property string loopbackPrefix: "app."
  readonly property string loopbackOutSuffix: ".out"
  readonly property var obsNamePattern: /^OBS(:|$)/

  readonly property real floorDb: -60
  readonly property real volumeStep: 0.05

  readonly property var nodes: Pipewire.nodes.values // qmllint disable missing-property
  readonly property var linkGroups: Pipewire.linkGroups.values // qmllint disable missing-property

  function isChain(node) { return !!node && (node.name === eqName || node.name === eqName + ".out") }
  function isObs(node) { return !!node && obsNamePattern.test(node.name) }
  function isPeakMonitor(node) { return !!node && node.name === peakMonitorName }
  function isLoopback(node) { return !!node && node.name.startsWith(loopbackPrefix) }
  function isLoopbackSink(node) { return isLoopback(node) && !node.isStream }

  readonly property var sinks: nodes.filter(n => n.audio && n.isSink && !n.isStream && !isChain(n) && !isLoopback(n))
  readonly property var sources: nodes.filter(n => n.audio && !n.isSink && !n.isStream)
  readonly property var loopbackOuts: nodes.filter(n => n.audio && n.isStream && isLoopback(n))
  readonly property var appStreams: {
    var seen = []
    return nodes.filter(n => {
      if (!n.audio || !n.isSink || !n.isStream || isChain(n) || isLoopback(n)) return false
      var out = loopbackOutOf(n)
      if (!out) return true
      if (seen.indexOf(out) >= 0) return false
      seen.push(out)
      return true
    })
  }
  readonly property var eq: nodes.find(n => n.name === eqName) || null
  readonly property var eqOut: nodes.find(n => n.name === eqName + ".out") || null

  function targetsOf(node) {
    var out = []
    for (let i = 0; i < linkGroups.length; i++)
      if (linkGroups[i].source === node && linkGroups[i].target) out.push(linkGroups[i].target)
    return out
  }

  function loopbackOutOf(stream) {
    var sink = targetsOf(stream).find(t => isLoopbackSink(t))
    if (!sink) return null
    var name = sink.name + loopbackOutSuffix
    return loopbackOuts.find(n => n.name === name) || null
  }

  function levelOf(stream) { return loopbackOutOf(stream) || stream }

  function sinkOf(node) {
    var targets = targetsOf(node)
    for (let i = 0; i < targets.length; i++) {
      if (targets[i].isStream) continue
      if (targets[i] === eq) return sinkOf(eqOut)
      if (isLoopbackSink(targets[i])) return sinkOf(loopbackOutOf(node))
      return targets[i]
    }
    return null
  }

  function isTappedByObs(node) {
    return targetsOf(node).some(t => isObs(t))
  }

  function obsInputOf(node) {
    var tap = targetsOf(node).find(t => isObs(t))
    return tap ? tap.name.replace(/^OBS:\s*/, "") : ""
  }

  readonly property var micListeners: {
    var streams = targetsOf(Pipewire.defaultAudioSource).filter(t => t.isStream && !isPeakMonitor(t))
    var names = []
    var out = []
    for (let i = 0; i < streams.length; i++) {
      let name = appName(streams[i])
      if (names.indexOf(name) >= 0) continue
      names.push(name)
      out.push(streams[i])
    }
    return out
  }

  function appEntry(node) {
    var p = node.properties || {}
    var keys = [p["application.process.binary"], p["application.name"], node.name]
    for (let i = 0; i < keys.length; i++) {
      if (!keys[i]) continue
      let entry = DesktopEntries.heuristicLookup(String(keys[i]))
      if (entry) return entry
    }
    return null
  }

  function appName(node) {
    if (!node) return ""
    if (isObs(node)) return "OBS"
    var entry = appEntry(node)
    if (entry) return entry.name
    var p = node.properties || {}
    return p["application.name"] || node.nickname || node.description || node.name
  }

  function appIcon(node) {
    var p = node.properties || {}
    var entry = appEntry(node)
    var name = p["application.icon_name"] || (entry ? entry.icon : "") || "audio-x-generic"
    return Quickshell.iconPath(name, "audio-x-generic")
  }

  function deviceName(node) {
    if (!node) return "--"
    return (node.nickname || node.description || node.name).replace(/ (Analog|Digital) (Stereo|Mono|Surround.*)$/, "")
  }

  function db(cubic) { return cubic > 0 ? 60 * Math.log(cubic) / Math.LN10 : -Infinity }
  function dbText(cubic) {
    var d = db(cubic)
    if (d <= floorDb) return "-inf"
    return (d > 0 ? "+" : "") + d.toFixed(1)
  }
  function meterPosition(peak) { return Math.max(0, Math.min(1, 1 - db(peak) / floorDb)) }

  function volumeIcon(volume, muted) {
    if (muted) return "\u{f075f}"
    if (volume > 0.66) return "\u{f057e}"
    if (volume > 0) return "\u{f0580}"
    return "\u{f057f}"
  }

  function nudge(node, delta) {
    if (!node || !node.audio || delta === 0) return
    node.audio.volume = Math.max(0, Math.min(1, node.audio.volume + (delta > 0 ? volumeStep : -volumeStep)))
  }

  function route(stream, target) {
    if (!stream) return
    var node = levelOf(stream)
    var serial = target && target.properties ? target.properties["object.serial"] : undefined
    if (target && serial !== undefined)
      Quickshell.execDetached(["pw-metadata", String(node.id), "target.object", String(serial), "Spa:Id"])
    else if (target) Quickshell.execDetached(["pw-metadata", String(node.id), "target.object", target.name])
    else Quickshell.execDetached(["pw-metadata", "-d", String(node.id), "target.object"])
  }
}

pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Services.Pipewire

Singleton {
  id: root

  // the eq name comes from configs/desktop/pipewire/mod.nu
  readonly property string eqName: "eq"
  // node.name of our own PwNodePeakMonitor streams
  readonly property string peakMonitorName: "quickshell"
  // obs names pulse captures after the app and pipewire captures "OBS: <source>"
  readonly property var obsNamePattern: /^OBS(:|$)/

  // meters bottom out here, quieter is silence for a mixer
  readonly property real floorDb: -60
  // one wheel notch, 20 to cross the range
  readonly property real volumeStep: 0.05

  // quickshell's qmltypes stub ObjectModel as opaque, so qmllint cannot see .values
  readonly property var nodes: Pipewire.nodes.values // qmllint disable missing-property
  readonly property var linkGroups: Pipewire.linkGroups.values // qmllint disable missing-property

  function isChain(node) { return !!node && (node.name === eqName || node.name === eqName + ".out") }
  function isObs(node) { return !!node && obsNamePattern.test(node.name) }
  function isPeakMonitor(node) { return !!node && node.name === peakMonitorName }

  readonly property var sinks: nodes.filter(n => n.audio && n.isSink && !n.isStream && !isChain(n))
  readonly property var sources: nodes.filter(n => n.audio && !n.isSink && !n.isStream)
  readonly property var appStreams: nodes.filter(n => n.audio && n.isSink && n.isStream && !isChain(n))
  readonly property var eq: nodes.find(n => n.name === eqName) || null
  readonly property var eqOut: nodes.find(n => n.name === eqName + ".out") || null

  function targetsOf(node) {
    var out = []
    for (let i = 0; i < linkGroups.length; i++)
      if (linkGroups[i].source === node && linkGroups[i].target) out.push(linkGroups[i].target)
    return out
  }

  // seen through the eq, null while unlinked
  function sinkOf(node) {
    var targets = targetsOf(node)
    for (let i = 0; i < targets.length; i++)
      if (!targets[i].isStream) return targets[i] === eq ? sinkOf(eqOut) : targets[i]
    return null
  }

  function isTappedByObs(node) {
    return targetsOf(node).some(t => isObs(t))
  }

  readonly property var micListeners: targetsOf(Pipewire.defaultAudioSource).filter(t => t.isStream && !isPeakMonitor(t))

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

  // devices carry long alsa names, the panel wants the product
  function deviceName(node) {
    if (!node) return "--"
    return (node.nickname || node.description || node.name).replace(/ (Analog|Digital) (Stereo|Mono|Surround.*)$/, "")
  }

  // quickshell volumes and peaks are cubic like wpctl, so db is 60 log10
  function db(cubic) { return cubic > 0 ? 60 * Math.log(cubic) / Math.LN10 : -Infinity }
  function dbText(cubic) {
    var d = db(cubic)
    if (d <= floorDb) return "-inf"
    return (d > 0 ? "+" : "") + d.toFixed(1)
  }
  function meterPosition(peak) { return Math.max(0, Math.min(1, 1 - db(peak) / floorDb)) }

  // md-volume mute / high / medium / low
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

  // null hands the stream back to the default sink
  function route(stream, target) {
    if (!stream) return
    if (target) Quickshell.execDetached(["pw-metadata", String(stream.id), "target.object", target.name])
    else Quickshell.execDetached(["pw-metadata", "-d", String(stream.id), "target.object"])
  }
}

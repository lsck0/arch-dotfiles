pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Services.Pipewire

// one view of the pipewire graph for the audio widgets: devices, lanes, app streams, who taps what
Singleton {
  id: root

  // configs/pipewire/chains.sh: sink lane.<name> with playback lane.<name>.out, headset eq sink eq with playback eq.out
  readonly property string lanePrefix: "lane."
  readonly property string eqName: "eq"
  // the eq switch is this unit's enablement, so it persists
  readonly property string eqUnit: "pipewire-chain@eq.service"
  // node.name of quickshell's own PwNodePeakMonitor capture streams
  readonly property string peakMonitorName: "quickshell"
  // obs names pulse captures after the app and pipewire captures "OBS: <source>"
  readonly property var obsNamePattern: /^OBS(:|$)/

  // meters bottom out here, quieter is silence for a mixer
  readonly property real floorDb: -60
  // one wheel notch, 20 to cross the range
  readonly property real volumeStep: 0.05

  readonly property var nodes: Pipewire.nodes.values
  readonly property var linkGroups: Pipewire.linkGroups.values

  function isLane(node) { return !!node && node.name.indexOf(lanePrefix) === 0 }
  function isChain(node) { return isLane(node) || (!!node && (node.name === eqName || node.name === eqName + ".out")) }
  function isObs(node) { return !!node && obsNamePattern.test(node.name) }
  function isPeakMonitor(node) { return !!node && node.name === peakMonitorName }

  readonly property var sinks: nodes.filter(n => n.audio && n.isSink && !n.isStream && !isChain(n))
  readonly property var sources: nodes.filter(n => n.audio && !n.isSink && !n.isStream)
  readonly property var lanes: nodes.filter(n => n.audio && n.isSink && !n.isStream && isLane(n))
  readonly property var appStreams: nodes.filter(n => n.audio && n.isSink && n.isStream && !isChain(n))
  readonly property var eq: nodes.find(n => n.name === eqName) || null
  readonly property var eqOut: nodes.find(n => n.name === eqName + ".out") || null

  function eqSet(on) { Quickshell.execDetached(["systemctl", "--user", on ? "enable" : "disable", "--now", eqUnit]) }

  function targetsOf(node) {
    var out = []
    for (var i = 0; i < linkGroups.length; i++)
      if (linkGroups[i].source === node && linkGroups[i].target) out.push(linkGroups[i].target)
    return out
  }

  // the sink or lane a stream plays into, seen through the eq, null while unlinked
  function sinkOf(node) {
    var targets = targetsOf(node)
    for (var i = 0; i < targets.length; i++)
      if (!targets[i].isStream) return targets[i] === eq ? sinkOf(eqOut) : targets[i]
    return null
  }

  function isTappedByObs(node) {
    return targetsOf(node).some(t => isObs(t))
  }

  // capture streams on the default source, minus the panel's own meters
  readonly property var micListeners: targetsOf(Pipewire.defaultAudioSource).filter(t => t.isStream && !isPeakMonitor(t))

  function appEntry(node) {
    var p = node.properties || {}
    var keys = [p["application.process.binary"], p["application.name"], node.name]
    for (var i = 0; i < keys.length; i++) {
      if (!keys[i]) continue
      var entry = DesktopEntries.heuristicLookup(String(keys[i]))
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
    if (isLane(node)) return node.description.toUpperCase()
    return (node.nickname || node.description || node.name).replace(/ (Analog|Digital) (Stereo|Mono|Surround.*)$/, "")
  }

  // quickshell volumes and peaks are cubic like wpctl, so db is 60 log10
  function db(cubic) { return cubic > 0 ? 60 * Math.log(cubic) / Math.LN10 : -Infinity }
  function dbText(cubic) {
    var d = db(cubic)
    if (d <= floorDb) return "-inf"
    return (d > 0 ? "+" : "") + d.toFixed(1)
  }
  // 0..1 meter position for a peak
  function meterPosition(peak) { return Math.max(0, Math.min(1, 1 - db(peak) / floorDb)) }

  // md-volume mute / high / medium / low
  function volumeIcon(volume, muted) {
    if (muted) return "\u{f075f}"
    if (volume > 0.66) return "\u{f057e}"
    if (volume > 0) return "\u{f0580}"
    return "\u{f057f}"
  }

  // one volumeStep in the direction of a wheel delta
  function nudge(node, delta) {
    if (!node || !node.audio || delta === 0) return
    node.audio.volume = Math.max(0, Math.min(1, node.audio.volume + (delta > 0 ? volumeStep : -volumeStep)))
  }

  // null target hands the stream back to its role lane or the default sink
  function route(stream, target) {
    if (!stream) return
    if (target) Quickshell.execDetached(["pw-metadata", String(stream.id), "target.object", target.name])
    else Quickshell.execDetached(["pw-metadata", "-d", String(stream.id), "target.object"])
  }
}

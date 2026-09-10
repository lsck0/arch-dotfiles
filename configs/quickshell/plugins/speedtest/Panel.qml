import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Adapted from omarchy-shell almost verbatim -- the shared gauge-cluster
// overlay (Ui/SpeedTestOverlay.qml, already ported and unchanged) dressed
// for the internet speed test: download and upload dials in Mbps, titled
// with the connection under test.
//
// Loaded on-demand through shell.qml's generic panel loader (`shell.summon`/
// `shell.hide`) -- the first real exercise of that machinery, which Phase 2
// built but nothing had used until now (Clipboard/AppSearch/Notifications
// are always-on background state instead, so they were wired as direct
// top-level instantiations; this plugin has no state to keep between runs,
// so lazy load-on-summon is the correct fit and matches upstream's design).
//
// Adaptations: `omarchy-network-speedtest` -> `network-speedtest` (this
// repo's configs/quickshell/scripts/network-speedtest.sh, symlinked into
// ~/.local/bin by configs/quickshell/link.sh -- verbatim script otherwise,
// only `omarchy-cmd-present curl` -> `command -v curl` since that helper
// has no local equivalent).
// `omarchy-network-status` (a bin/ script with no local equivalent) ->
// this repo's own plugins/bar/widgets/network-details.sh, which already
// produces a `{ssid, device, ...}` JSON shape Network.qml relies on for the
// same purpose -- reused here instead of porting a second connection-name
// lookup.
Item {
  id: root

  property var shell: null
  property var manifest: null

  readonly property string configRoot:
    Quickshell.env("HOME") + "/projects/arch-dotfiles/configs/quickshell"
  readonly property string networkDetailsScript:
    configRoot + "/plugins/bar/widgets/network-details.sh"
  readonly property string speedTestScript:
    configRoot + "/scripts/network-speedtest.sh"
  readonly property string statePath:
    (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state"))
      + "/quickshell/network-speedtest.json"

  property bool opened: false
  property bool settingsLoaded: false
  property string pingMs: ""
  property string lastDownloadMbps: ""
  property string lastUploadMbps: ""
  property string connectionName: ""

  property bool running: false
  property bool expectedStop: false
  property bool pendingRun: false
  property string phase: ""        // "down" | "up" | ""
  property string stderrText: ""
  property string downloadMbps: ""
  property string uploadMbps: ""
  property string error: ""

  readonly property real downloadValue: toMbps(downloadMbps)
  readonly property real uploadValue: toMbps(uploadMbps)

  function toMbps(raw) {
    var value = parseFloat(raw)
    return isFinite(value) && value > 0 ? value : 0
  }

  function open(payloadJson) {
    var payload = {}
    try { payload = JSON.parse(payloadJson || "{}") || {} } catch (e) {}
    if (payload.connection !== undefined) root.connectionName = String(payload.connection)
    else refreshConnectionName()
    root.opened = true
    runSpeedTest()
  }

  function close() {
    root.opened = false
    root.pendingRun = false
    phaseTimer.stop()
    // Clear the phase before killing the process: onExited advances to the
    // upload phase when it still reads "down".
    root.phase = ""
    root.running = false
    if (speedTestProc.running) {
      root.expectedStop = true
      speedTestProc.running = false
    }
  }

  function dismiss() {
    if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide((root.manifest && root.manifest.id) || "panel.speedtest")
    else close()
  }

  function refreshConnectionName() {
    root.connectionName = ""
    statusProc.running = false
    statusProc.running = true
  }

  function updateSpeedTestLine(line) {
    var value = parseFloat(line)
    if (!isFinite(value) || value < 0) return

    if (phase === "down") downloadMbps = String(value)
    else if (phase === "up") uploadMbps = String(value)
  }

  function loadResults(raw) {
    if (root.settingsLoaded) return
    root.settingsLoaded = true
    try {
      var saved = JSON.parse(raw || "{}") || {}
      root.pingMs = saved.pingMs ? String(saved.pingMs) : ""
      root.lastDownloadMbps = saved.downloadMbps ? String(saved.downloadMbps) : ""
      root.lastUploadMbps = saved.uploadMbps ? String(saved.uploadMbps) : ""
    } catch (e) {}
  }

  function saveResults() {
    if (!root.settingsLoaded) return
    resultsFile.setText(JSON.stringify({
      version: 1,
      connection: root.connectionName,
      pingMs: root.pingMs,
      downloadMbps: root.lastDownloadMbps,
      uploadMbps: root.lastUploadMbps
    }, null, 2) + "\n")
  }

  function runSpeedTest() {
    if (speedTestProc.running) {
      // A dismissal's SIGTERM is still in flight; Process.running stays true
      // until the child exits, so queue the fresh run for onExited.
      if (expectedStop) pendingRun = true
      return
    }
    error = ""
    downloadMbps = ""
    uploadMbps = ""
    running = true
    pingProc.running = true
    startPhase("down")
  }

  function startPhase(nextPhase) {
    expectedStop = false
    phase = nextPhase
    stderrText = ""
    speedTestProc.command = ["bash", root.speedTestScript, nextPhase]
    speedTestProc.running = true
    phaseTimer.restart()
  }

  function stopPhase() {
    phaseTimer.stop()
    if (speedTestProc.running) {
      expectedStop = true
      speedTestProc.running = false
      return
    }
    finishPhase()
  }

  function finishPhase() {
    if (phase === "down") {
      startPhase("up")
      return
    }

    phase = ""
    running = false
    expectedStop = false
    root.lastDownloadMbps = root.downloadMbps
    root.lastUploadMbps = root.uploadMbps
    root.saveResults()
  }

  FileView {
    id: resultsFile
    path: root.statePath
    watchChanges: false
    atomicWrites: true
    printErrors: false
    onLoaded: root.loadResults(text())
    onLoadFailed: root.loadResults("")
  }

  Process {
    id: pingProc
    command: ["ping", "-c", "1", "-W", "2", "1.1.1.1"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var match = String(text || "").match(/time[=<]([0-9.]+) ms/)
        root.pingMs = match ? match[1] : ""
        root.saveResults()
      }
    }
  }

  Process {
    id: speedTestProc
    stdout: SplitParser { onRead: function(line) { root.updateSpeedTestLine(line) } }
    // Exit and stream-finished have no guaranteed order: when a failed exit
    // beat the collector and published the generic message, replace it with
    // the specific one once it lands.
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.stderrText = String(text || "").trim()
        if (root.error !== "" && root.stderrText !== "") root.error = root.stderrText
      }
    }
    onExited: function(exitCode) {
      phaseTimer.stop()

      if (root.pendingRun) {
        root.pendingRun = false
        root.expectedStop = false
        if (root.opened) Qt.callLater(root.runSpeedTest)
        return
      }

      if (!root.expectedStop && exitCode !== 0) {
        root.error = root.stderrText || "Speed test failed"
        root.phase = ""
        root.running = false
        return
      }

      root.expectedStop = false
      root.finishPhase()
    }
  }

  Timer {
    id: phaseTimer
    interval: 5000
    repeat: false
    onTriggered: root.stopPhase()
  }

  // Names the connection under test when the summoner didn't.
  Process {
    id: statusProc
    command: ["bash", root.networkDetailsScript]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var d = JSON.parse(text || "{}")
          if (d.ssid) root.connectionName = d.ssid
          else if (d.device) root.connectionName = d.device
        } catch (e) {}
      }
    }
  }

  SpeedTestOverlay {
    fontFamily: Style.font.family
    layerNamespace: "quickshell-network-speedtest"
    title: root.connectionName
    leftLabel: "DOWNLOAD"
    rightLabel: "UPLOAD"
    runAgainTooltip: "Measure again via fast.com"
    running: root.running
    leftValue: root.downloadValue
    rightValue: root.uploadValue
    leftLive: root.running && root.phase === "down"
    rightLive: root.running && root.phase === "up"
    statusText: (root.pingMs !== "" ? "PING " + root.pingMs + " ms" : "")
      + (!root.running && root.lastDownloadMbps !== "" && root.lastUploadMbps !== ""
        ? (root.pingMs !== "" ? "  ·  " : "") + "LAST " + root.lastDownloadMbps + " / " + root.lastUploadMbps + " Mbps" : "")
    error: root.error
    open: root.opened
    onCloseRequested: root.dismiss()
    onRunAgainRequested: root.runSpeedTest()
  }
}

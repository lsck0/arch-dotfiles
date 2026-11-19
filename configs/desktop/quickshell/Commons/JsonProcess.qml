import QtQuick
import Quickshell.Io

QtObject {
  id: root

  property var command: []
  property int intervalMs: 0
  property int minAgeMs: 0
  property real lastRunMs: 0
  property bool streaming: false
  property alias running: proc.running
  // backoff for retryStart, the last delay repeating; empty means no retries
  property var retryDelaysMs: []
  property int retryCount: 0
  // the current run printed something to decode; a run that ends without (not started, killed, no output, a stream
  // that never printed a line) fails
  property bool decoded: false
  readonly property int outputGraceMs: 1000

  signal parsed(var data)
  signal failed(string error)

  function run() {
    if (proc.running) return
    lastRunMs = Date.now()
    decoded = false
    proc.running = true
  }

  function refresh() {
    if (minAgeMs > 0 && Date.now() - lastRunMs < minAgeMs) return
    run()
  }

  // run again after the next backoff delay; output that is no JSON retries on its own
  function retryStart() {
    if (retryDelaysMs.length === 0) return
    retryTimer.interval = retryDelaysMs[Math.min(retryCount, retryDelaysMs.length - 1)]
    retryTimer.restart()
  }

  function retryStop() {
    retryCount = 0
    retryTimer.stop()
  }

  function decode(text) {
    root.decoded = true
    var data
    try { data = JSON.parse(text) } catch (e) { root.failed(String(e)); root.retryStart(); return }
    root.parsed(data)
  }

  property StdioCollector whole: StdioCollector {
    waitForEnd: true
    onStreamFinished: root.decode(text)
  }

  property SplitParser lines: SplitParser {
    onRead: function (line) { if (line) root.decode(line) }
  }

  property Process process: Process {
    id: proc
    command: root.command
    stdout: root.streaming ? root.lines : root.whole
    // the collector may finish just after the exit, so the check waits a moment for it
    onRunningChanged: if (!running) root.noOutput.restart()
    Component.onDestruction: running = false
  }

  property Timer poll: Timer {
    interval: Math.max(1, root.intervalMs)
    running: root.intervalMs > 0
    repeat: true
    triggeredOnStart: true
    onTriggered: root.run()
  }

  property Timer noOutput: Timer {
    interval: root.outputGraceMs
    onTriggered: {
      if (root.decoded || proc.running) return
      root.failed("no output")
      root.retryStart()
    }
  }

  // a run still going when the delay ends (one started by a refresh meanwhile) reports for itself; a retry dropped
  // here would end the backoff with the error left on screen
  property Timer retryTimer: Timer {
    onTriggered: {
      if (proc.running) { restart(); return }
      root.retryCount++
      root.run()
    }
  }
}

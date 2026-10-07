import QtQuick
import Quickshell.Io

/**
 * JsonProcess: runs a command that prints JSON and hands back the decoded value.
 *
 * One type for the three shapes the shell needs:
 *   one-shot   call refresh(); parsed fires once the command exits, with all of stdout
 *   polled     intervalMs > 0 also refreshes at start and every intervalMs; bind it to 0 to pause
 *   streaming  streaming: true decodes every stdout line on its own; start with running: true or refresh()
 *
 * Properties:
 *   command     argv list
 *   intervalMs  poll period, 0 means no timer
 *   minAgeMs    refresh() is a no-op while the last run is younger than this; polls ignore it
 *   streaming   one JSON value per line instead of one per run
 *   running     the process is alive; set false to stop a stream
 *
 * Signals:
 *   parsed(data)   one decoded value
 *   failed(error)  stdout, or one line of it, was not JSON (an empty run counts)
 *
 * Usage:
 *   JsonProcess {
 *     command: [Paths.barWidget("agent-usage.py")]
 *     intervalMs: 10 * 60 * 1000
 *     onParsed: function (data) { root.usage = data }
 *   }
 */
QtObject {
  id: root

  property var command: []
  property int intervalMs: 0
  property int minAgeMs: 0
  property real lastRunMs: 0
  property bool streaming: false
  property alias running: process.running

  signal parsed(var data)
  signal failed(string error)

  // a refresh during a run is dropped, the run in flight answers it
  function run() {
    if (process.running) return
    lastRunMs = Date.now()
    process.running = true
  }

  // hover and open refreshes, rate-limited by minAgeMs
  function refresh() {
    if (minAgeMs > 0 && Date.now() - lastRunMs < minAgeMs) return
    run()
  }

  // parse outside the handler call so a throwing onParsed is not reported as bad json
  function decode(text) {
    var data
    try { data = JSON.parse(text) } catch (e) { root.failed(String(e)); return }
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
    id: process
    command: root.command
    stdout: root.streaming ? root.lines : root.whole
    // quickshell does not reap helpers on reload, stop on teardown
    Component.onDestruction: running = false
  }

  property Timer poll: Timer {
    interval: Math.max(1, root.intervalMs)
    running: root.intervalMs > 0
    repeat: true
    triggeredOnStart: true
    onTriggered: root.run()
  }
}

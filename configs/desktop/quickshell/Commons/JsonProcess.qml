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

  signal parsed(var data)
  signal failed(string error)

  function run() {
    if (proc.running) return
    lastRunMs = Date.now()
    proc.running = true
  }

  function refresh() {
    if (minAgeMs > 0 && Date.now() - lastRunMs < minAgeMs) return
    run()
  }

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
    id: proc
    command: root.command
    stdout: root.streaming ? root.lines : root.whole
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

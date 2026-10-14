import QtQuick
import Quickshell.Io

// start() during a stop in flight queues one restart, so an old process never answers for a new run
QtObject {
  id: root

  property var command: []
  property var values: ({})
  property string error: ""
  readonly property alias running: proc.running
  // between start() and stop(), so a stopped run's exit is not an error
  property bool wanted: false
  property bool queued: false

  function start() {
    queued = proc.running && !wanted
    if (proc.running) return
    wanted = true
    values = {}
    error = ""
    proc.running = true
  }

  function stop() {
    wanted = false
    queued = false
    proc.running = false
  }

  // exit and stderr eof race; prefer the specific message
  property StdioCollector errors: StdioCollector {
    waitForEnd: true
    onStreamFinished: if (root.error !== "" && text.trim() !== "") root.error = text.trim()
  }

  property SplitParser lines: SplitParser {
    onRead: function (line) {
      var split = line.indexOf(" ")
      if (split > 0) root.values = Util.mapSet(root.values, line.slice(0, split), line.slice(split + 1))
    }
  }

  property Process process: Process {
    id: proc
    command: root.command
    stdout: root.lines
    stderr: root.errors
    onExited: function (exitCode) {
      if (root.wanted && exitCode !== 0) root.error = root.errors.text.trim() || "exited with " + exitCode
      root.wanted = false
      if (root.queued) Qt.callLater(root.start)
    }
  }
}

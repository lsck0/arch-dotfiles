import QtQuick
import Quickshell.Io

/**
 * KeyValueProcess: a stoppable, restartable run of a command that prints "<key> <value>" lines.
 *
 * Properties:
 *   command  argv list
 *   values   latest value per key of the current run, cleared by start()
 *   error    stderr of a run that failed on its own, "" otherwise
 *   running  the process is alive
 *
 * start() during a run is ignored, during a stop still in flight it queues one restart for the exit, so an old
 * process never answers for a new run.
 *
 * Usage:
 *   KeyValueProcess { id: test; command: [Paths.script("disk-speedtest.sh")] }
 *   Text { text: test.values.read || "" }
 */
QtObject {
  id: root

  property var command: []
  property var values: ({})
  property string error: ""
  readonly property alias running: process.running
  // between start() and stop(), so a stopped run's exit is not an error
  property bool wanted: false
  property bool queued: false

  function start() {
    queued = process.running && !wanted
    if (process.running) return
    wanted = true
    values = {}
    error = ""
    process.running = true
  }

  function stop() {
    wanted = false
    queued = false
    process.running = false
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
    id: process
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

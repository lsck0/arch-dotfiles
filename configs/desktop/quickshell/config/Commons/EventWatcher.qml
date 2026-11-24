import QtQuick
import Quickshell.Io

// A long-running monitor command (nmcli monitor, udisksctl monitor, gdbus monitor) whose every line asks for one
// fired(), coalesced over debounceMs; an exit starts it again after restartMs. setpriv ends it with the shell.
QtObject {
  id: root

  property var command: []
  property int debounceMs: 400
  // fire at most once per debounceMs while lines keep coming, instead of only once they pause
  property bool throttle: false
  property int restartMs: 5000

  signal fired()

  // asks for a fired() as a line would, for a change the monitor does not see
  function queue() {
    if (!throttle || !debounceTimer.running) debounceTimer.restart()
  }

  property Process process: Process {
    id: proc
    running: true
    command: ["setpriv", "--pdeathsig", "TERM"].concat(root.command)
    Component.onDestruction: running = false
    stdout: SplitParser { onRead: root.queue() }
    onExited: restartTimer.restart()
  }

  property Timer debounce: Timer {
    id: debounceTimer
    interval: root.debounceMs
    onTriggered: root.fired()
  }

  property Timer restart: Timer {
    id: restartTimer
    interval: root.restartMs
    onTriggered: proc.running = true
  }
}

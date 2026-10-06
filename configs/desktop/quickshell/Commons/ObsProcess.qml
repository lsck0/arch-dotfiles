pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

// whether obs runs, shared by the bar's obs widget and the notification service's auto dnd
Singleton {
  id: root

  property bool running: false

  // toplevel changes catch launch and window close; the slow poll catches a quit from the tray
  function probe() {
    if (!proc.running) proc.running = true
  }

  Process {
    id: proc
    // -x, pgrep -f would match its own command line
    command: ["pgrep", "-x", "obs"]
    onExited: function (exitCode) { root.running = exitCode === 0 }
  }

  // obs may already run when the shell starts
  Component.onCompleted: root.probe()

  Connections {
    target: ToplevelManager.toplevels
    function onValuesChanged() { root.probe() }
  }

  // only while obs runs, to catch a tray quit that closes no window; a launch is caught by the toplevel event
  Timer {
    interval: 60000
    running: root.running
    repeat: true
    onTriggered: root.probe()
  }
}

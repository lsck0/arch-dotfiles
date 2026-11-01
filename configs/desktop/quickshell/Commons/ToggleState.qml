import QtQuick
import Quickshell.Io

// One toggle script's state, as its `get` prints it: read on start and again whenever ToggleEvents reports the script
// changed. A reader needed only while a panel is open sets active and reads nothing while inactive.
QtObject {
  id: root

  required property string script
  property bool active: true
  property string state: ""
  readonly property string path: Paths.toggle(script)
  // a refresh asked for while a get runs, which may have read the old state: run once more after it
  property bool again: false

  function refresh() {
    if (proc.running) again = true
    else proc.running = true
  }

  onActiveChanged: if (active) refresh()
  Component.onCompleted: if (active) refresh()

  property Process process: Process {
    id: proc
    command: [root.path, "get"]
    stdout: StdioCollector {
      id: output
      waitForEnd: true
    }
    onExited: {
      root.state = (output.text || "").trim()
      if (root.again) {
        root.again = false
        proc.running = true
      }
    }
  }

  property Connections events: Connections {
    target: ToggleEvents
    function onChanged(script) { if (root.active && script === root.script) root.refresh() }
  }
}

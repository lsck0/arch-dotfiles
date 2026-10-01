import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

BarIndicator {
  id: root

  readonly property string toggleScript: Paths.toggle("toggle-keep-awake.sh")

  active: false
  activeText: "\u{f0176}"
  inactiveText: "\u{f0176}"
  activeTooltipText: "Allow Idle Lock & Screensaver"
  inactiveTooltipText: "Keep Awake"

  function refresh() {
    if (!checkProc.running) checkProc.running = true
  }

  Process {
    id: checkProc
    command: [root.toggleScript, "get"]
    stdout: StdioCollector {
      id: checkOutput
      waitForEnd: true
    }
    onExited: root.active = (checkOutput.text || "").trim() === "on"
  }

  Timer {
    interval: 30000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  onPressed: function() {
    Quickshell.execDetached([root.toggleScript, "toggle"])
    Qt.callLater(root.refresh)
  }
}

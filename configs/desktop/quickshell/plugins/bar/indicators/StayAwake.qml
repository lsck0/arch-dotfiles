import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

BarIndicator {
  id: root

  readonly property string toggleScript: Paths.toggle("toggle-keep-awake.nu")

  active: false
  activeText: "\u{f0176}"
  inactiveText: "\u{f0176}"
  activeTooltipText: "Allow idle lock"
  inactiveTooltipText: "Keep awake"

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

  Component.onCompleted: refresh()

  Connections {
    target: ToggleEvents
    function onChanged(script) { if (script === "toggle-keep-awake.nu") root.refresh() }
  }

  onPressed: function() { Quickshell.execDetached(["uwsm-app", "-s", "b", "--", root.toggleScript, "toggle"]) }
}

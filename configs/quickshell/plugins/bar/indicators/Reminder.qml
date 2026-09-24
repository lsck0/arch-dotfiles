import QtQuick
import Quickshell
import Quickshell.Io
import qs.Ui

// Adapted from omarchy-shell: omarchy-reminder -> this repo's own configs/quickshell/scripts/reminder.sh.
BarIndicator {
  id: root

  readonly property string reminderScript: Quickshell.env("HOME") + "/.local/bin/reminder"

  property int reminderCount: 0
  property string tooltip: ""

  active: reminderCount > 0
  activeText: "󰢌"
  inactiveText: "󰢌"
  activeTooltipText: tooltip
  inactiveTooltipText: tooltip

  function refresh() {
    if (!jsonProc.running) jsonProc.running = true
  }

  function openReminderFlow() {
    Quickshell.execDetached([root.reminderScript, "-i"])
  }

  function update(raw) {
    try {
      var data = JSON.parse(raw || "{}")
      root.reminderCount = Number(data.count || 0)
      root.tooltip = String(data.tooltip || "")
    } catch (e) {
      root.reminderCount = 0
      root.tooltip = ""
    }
  }

  Process {
    id: jsonProc
    command: [root.reminderScript, "show", "--json"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.update(text)
    }
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        root.reminderCount = 0
        root.tooltip = ""
      }
    }
  }

  // Was 5000ms.
  Timer { interval: 10000; running: true; repeat: true; triggeredOnStart: true; onTriggered: root.refresh() }

  onPressed: function() {
    root.openReminderFlow()
  }
}

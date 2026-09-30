import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

BarIndicator {
  id: root

  readonly property string reminderScript: Paths.script("reminder.sh")

  property int reminderCount: 0
  property string tooltip: ""

  active: reminderCount > 0
  activeText: "\u{f088c}"
  inactiveText: "\u{f088c}"
  activeTooltipText: tooltip
  inactiveTooltipText: tooltip

  function refresh() {
    if (!jsonProc.running) jsonProc.running = true
  }

  function openReminderFlow() {
    Quickshell.execDetached(Paths.ipcCall("shell", "summon", "panel.reminders", "{}"))
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

  Timer { interval: 10000; running: true; repeat: true; triggeredOnStart: true; onTriggered: root.refresh() }

  onPressed: function() {
    root.openReminderFlow()
  }
}

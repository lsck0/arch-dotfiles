import QtQuick
import Quickshell
import Quickshell.Io
import qs.Ui

// Adapted from omarchy-shell: omarchy-reminder -> this repo's own
// scripts/reminder.sh. Two real differences from upstream, both matching
// this repo's established Dnd.qml/StayAwake.qml pattern:
//   - omarchy-reminder's own `extractData(raw)` call goes through
//     BarIndicator.qml's `Util.parseModuleJson` -- never implemented
//     locally (nothing else needed it; Dnd.qml/StayAwake.qml already
//     bypass it with their own inline parsing). Parses the JSON directly
//     here instead of adding that function for this one call site.
//   - upstream refreshes only via Component.onCompleted plus an
//     indicatorHost-driven `onRefreshRequested` signal -- this repo's
//     simplified Indicators.qml never sets `indicatorHost` (see its own
//     header), so that signal path is dead here. Added a poll Timer
//     instead, matching Dnd.qml/StayAwake.qml's shape (interval tuned
//     separately below, see the Timer's own comment).
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

  // Was 5000ms. Unlike Dnd/StayAwake, this is the *only* update path --
  // setting/clearing a reminder happens through a separate component
  // (ReminderFlow.qml, or the `reminder` CLI directly) with no reference
  // back to this indicator to push a refresh -- so kept tighter than the
  // 20s used for the pure catch-up polls. 10s still cuts process count
  // in half. See TODO.md's "three independent poll timers" perf item.
  Timer { interval: 10000; running: true; repeat: true; triggeredOnStart: true; onTriggered: root.refresh() }

  onPressed: function() {
    if (root.reminderCount > 0) Quickshell.execDetached([root.reminderScript, "show"])
    else root.openReminderFlow()
  }
}

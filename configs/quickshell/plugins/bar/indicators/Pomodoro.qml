import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

BarIndicator {
  id: root

  readonly property string pomodoroScript: Paths.script("pomodoro.sh")
  property bool running: false
  property string phase: "idle"
  property string tooltip: "Pomodoro: off"

  active: running
  // break phase shows the coffee cup
  activeText: phase === "work" ? "\u{f051f}" : "\u{f0176}"
  inactiveText: "\u{f051f}"
  activeTooltipText: tooltip
  inactiveTooltipText: tooltip

  function refresh() {
    if (!jsonProc.running) jsonProc.running = true
  }

  function update(raw) {
    try {
      var d = JSON.parse(raw || "{}")
      root.running = !!d.running
      root.phase = String(d.phase || "idle")
      root.tooltip = String(d.tooltip || "Pomodoro: off")
    } catch (e) {
      root.running = false
      root.phase = "idle"
      root.tooltip = "Pomodoro: off"
    }
  }

  Process {
    id: jsonProc
    command: [root.pomodoroScript, "status", "--json"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.update(text)
    }
    onExited: function(exitCode) {
      if (exitCode !== 0) root.running = false
    }
  }

  // no push path, poll like Reminder.qml
  Timer { interval: 30000; running: true; repeat: true; triggeredOnStart: true; onTriggered: root.refresh() }

  onPressed: function() {
    Quickshell.execDetached([root.pomodoroScript, "toggle"])
    Qt.callLater(root.refresh)
  }
}

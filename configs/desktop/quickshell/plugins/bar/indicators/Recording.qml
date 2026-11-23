import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// record.nu's transient unit: read on start and on every `toggles changed record.nu`, which record.nu sends on start
// and the unit's ExecStopPost on any end, so nothing polls.
BarIndicator {
  id: root

  readonly property string unit: "screen-record.service"
  readonly property string script: "record.nu"
  readonly property string recordPath: Paths.dotfiles + "/configs/desktop/hyprland/" + script

  property string file: ""
  property real startedSec: 0
  property real nowSec: 0
  // a refresh asked for while a read runs, which may have seen the old state: read once more after it
  property bool again: false

  function refresh() {
    if (reader.running) again = true
    else reader.running = true
  }

  function apply(text) {
    var fields = {}
    for (const line of text.split("\n")) {
      const at = line.indexOf("=")
      if (at > 0) fields[line.slice(0, at)] = line.slice(at + 1)
    }
    // deactivating while ExecStopPost runs already counts as stopped
    active = fields.ActiveState === "active"
    file = active ? (fields.Description || "") : ""
    startedSec = Number(String(fields.ActiveEnterTimestamp || "").replace("@", "")) || 0
  }

  text: "\u{f044a}"
  foreground: Colors.urgentText
  tooltipText: "Stop recording" + (startedSec > 0 && nowSec > 0 ? " " + Util.clock(nowSec - startedSec) : "") + "\n" + file

  // the bar shows the tooltip text as of the hover, so the elapsed time is taken then instead of ticking
  onEntered: {
    nowSec = Date.now() / 1000
    if (bar) bar.showTooltip(root, tooltipText)
  }
  onPressed: function() { Quickshell.execDetached(["uwsm-app", "-s", "b", "--", recordPath, "stop"]) }

  Component.onCompleted: refresh()

  Process {
    id: reader
    command: ["systemctl", "--user", "show", "--timestamp=unix", "-p", "ActiveState", "-p", "Description",
      "-p", "ActiveEnterTimestamp", root.unit]
    stdout: StdioCollector {
      id: output
      waitForEnd: true
    }
    onExited: {
      root.apply(output.text || "")
      if (root.again) {
        root.again = false
        reader.running = true
      }
    }
  }

  Connections {
    target: ToggleEvents
    function onChanged(script) { if (script === root.script) root.refresh() }
  }
}

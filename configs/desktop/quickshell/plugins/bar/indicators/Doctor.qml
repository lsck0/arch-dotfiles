import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

BarIndicator {
  id: root

  readonly property string findingsPath: {
    var base = String(Quickshell.env("XDG_STATE_HOME") || "").trim() || (Paths.home + "/.local/state")
    return base.replace(/\/+$/, "") + "/doctor/findings"
  }
  property var findings: []

  active: findings.length > 0
  activeText: "\u{f04d9}"
  inactiveText: "\u{f04d9}"
  activeTooltipText: findings.join("\n")
  useActiveColor: true

  function apply(text) {
    root.findings = String(text || "").split("\n").filter(function (line) { return line.trim() !== "" })
  }

  FileView {
    path: root.findingsPath
    watchChanges: true
    printErrors: false
    onLoaded: { root.apply(text()); Util.rearmWatch(this) }
    onLoadFailed: root.findings = []
    onFileChanged: reload()
  }

  onPressed: Quickshell.execDetached(["systemctl", "--user", "start", "--no-block", "doctor-check.service"])
}

import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

BarIndicator {
  ToggleState {
    id: keepAwake
    script: "toggle-keep-awake.nu"
  }

  active: keepAwake.state === "on"
  activeText: "\u{f0176}"
  activeTooltipText: "Allow idle lock"
  inactiveTooltipText: "Keep awake"

  onPressed: function() { Quickshell.execDetached(["uwsm-app", "-s", "b", "--", keepAwake.path, "toggle"]) }
}

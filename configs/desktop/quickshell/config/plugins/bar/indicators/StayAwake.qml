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
  text: "\u{f0176}"
  tooltipText: "Allow idle lock"

  onPressed: function() { Quickshell.execDetached(["uwsm-app", "-s", "b", "--", keepAwake.path, "toggle"]) }
}

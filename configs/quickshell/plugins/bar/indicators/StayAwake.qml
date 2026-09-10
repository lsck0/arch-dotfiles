import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Adapted from upstream, which reads bar.shell.firstPartyServiceFor(
// "omarchy.idle") — an idle-management service plugin this repo doesn't
// have. Polls toggles/toggle-keep-awake.sh directly instead, matching
// TODO.md's Phase 3 instruction: wire to existing toggles/*.sh, don't
// reimplement the toggle logic itself.
BarIndicator {
  id: root

  readonly property string toggleScript: Quickshell.env("HOME") + "/projects/arch-dotfiles/toggles/toggle-keep-awake.sh"

  active: false
  activeText: "󰅶"
  inactiveText: "󰅶"
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

  // Was 5000ms. Kept tighter than Dnd.qml/Toggles.qml's 20s: unlike a
  // plain on/off toggle, this poll is the only way to notice the
  // systemd-inhibit process behind "keep awake" dying on its own (crash,
  // OOM, manual kill) -- there's no write event to push-detect that, only
  // re-checking. 15s still cuts process count by 3x. See research/ROADMAP.md's "Post-Phase-8" note for the
  // interval choices and why FileView push updates were rejected.
  Timer {
    interval: 15000
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

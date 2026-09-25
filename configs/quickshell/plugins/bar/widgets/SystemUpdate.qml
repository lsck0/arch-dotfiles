import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Adapted from upstream, which is omarchy-specific end to end: its update check shells out to `omarchy-update-available` (a distro binary) and its click action launches `omarchy-launch-floating-terminal-with-presentation omarchy-update` (a distro CLI wrapper around a floating-terminal convention this repo has no equivalent of). Neither exists here, so: - update check: `checkupdates` (pacman-contrib, already installed) for official repos. Doesn't cover AUR/yay-only updates, which is a real gap vs. upstream's presumably-fuller check — left as-is rather than guessing at a yay invocation's exact output-parsing contract. - click action: launches this repo's own `scripts/system-update.sh` (interactive, prompts before doing anything) in a plain new ghostty window — not a floating/centered one, since no floating-terminal window-rule convention exists anywhere else in this repo to match; inventing one wasn't part of porting this widget. - dropped upstream's IpcHandler + broadcast() cross-monitor-sync mechanism: no other widget in this repo uses a per-widget IpcHandler or broadcast(), Bar.qml's own single `target: "bar"` IpcHandler is the only IPC surface every other widget shares.
BarWidget {
  id: root
  moduleName: "system-update"

  property bool updateAvailable: false

  function refresh() {
    if (!updateProc.running) updateProc.running = true
  }

  // `/usr/local/bin/system-update.sh` was a path nothing in this repo creates, so clicking the indicator opened a terminal that failed and closed.
  function runUpdate() {
    Quickshell.execDetached(["ghostty", "-e", Paths.bin("system-update")])
  }

  visible: updateAvailable
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Process {
    id: updateProc
    // checkupdates exits 0 with output when updates are pending, exits 2 with no output when there's nothing to do (its own documented contract) — read stdout rather than trust the exit code alone, since some transient failure modes also exit non-zero.
    command: ["bash", "-c", "checkupdates 2>/dev/null"]
    stdout: StdioCollector {
      id: updateOutput
      waitForEnd: true
    }
    onExited: function(exitCode) {
      root.updateAvailable = (updateOutput.text || "").trim().length > 0
    }
  }

  Timer {
    interval: 21600000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  // Accent neon backlight behind the glyph: the widget only shows at all when updates are pending.
  Rectangle {
    anchors.centerIn: parent
    width: Style.bar.iconCanvas
    height: width
    radius: width / 2
    color: Color.accent
    visible: Style.fx.glow > 0
    opacity: Style.fx.glowAlpha(0.8)
    layer.enabled: true
    layer.effect: MultiEffect {
      blurEnabled: true
      blur: 1.0
      blurMax: Style.fx.glowRadius
      autoPaddingEnabled: true
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: ""
    slotSize: Style.bar.statusSlot
    fontSize: Style.font.caption
    tooltipText: "Pending system updates"
    onPressed: root.runUpdate()
  }
}

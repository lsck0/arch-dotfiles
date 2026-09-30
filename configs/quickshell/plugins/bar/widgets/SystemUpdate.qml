import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// checkupdates covers official repos only, not aur
BarWidget {
  id: root
  moduleName: "system-update"

  property bool updateAvailable: false

  function refresh() {
    if (!updateProc.running) updateProc.running = true
  }

  function runUpdate() {
    Quickshell.execDetached(["ghostty", "-e", Paths.script("system-update.sh")])
  }

  visible: updateAvailable
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Process {
    id: updateProc
    // trust stdout, not the exit code: failures also exit non-zero
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
    interval: 6 * 60 * 60 * 1000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  Rectangle {
    anchors.centerIn: parent
    width: Style.bar.iconCanvas
    height: width
    radius: width / 2
    color: Color.accent
    visible: Style.fx.glow > 0
    opacity: Style.fx.glowAlpha(0.8)
    layer.enabled: Style.fx.glow > 0
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
    text: "\u{f021}"
    slotSize: Style.bar.statusSlot
    fontSize: Style.font.caption
    tooltipText: "Pending system updates"
    onPressed: root.runUpdate()
  }
}

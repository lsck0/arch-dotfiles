import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Much simpler than omarchy-shell's Agents plugin (a full multi-provider
// usage dashboard hitting Anthropic's OAuth-protected usage endpoint for
// real plan-limit percentages, session/weekly reset countdowns, Codex,
// Fireworks balance tracking...). That endpoint isn't publicly documented
// and this repo has no client for it, so this only reports what's honestly
// derivable from local data: today's token counts from Claude Code's own
// session transcripts, not quota percentage. See agent-usage.sh.
BarWidget {
  id: root
  moduleName: "agents"

  property int inputTokens: 0
  property int outputTokens: 0
  property int cacheTokens: 0

  readonly property int totalTokens: inputTokens + outputTokens + cacheTokens
  visible: totalTokens > 0

  implicitWidth: label.implicitWidth + Style.spacing.controlPaddingX * 2
  implicitHeight: barSize

  Rectangle {
    anchors.fill: parent
    radius: Style.cornerRadius
    color: mouseArea.containsMouse ? Style.hoverFill : "transparent"
    Behavior on color { ColorAnimation { duration: 100 } }
  }

  function refresh() {
    if (!usageProc.running) usageProc.running = true
  }

  function formatTokens(n) {
    if (n >= 1000000) return (n / 1000000).toFixed(1) + "M"
    if (n >= 1000) return (n / 1000).toFixed(1) + "K"
    return String(n)
  }

  Process {
    id: usageProc
    command: [Quickshell.env("HOME") + "/projects/arch-dotfiles/configs/quickshell/plugins/bar/widgets/agent-usage.sh"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var d = JSON.parse(text || "{}")
          root.inputTokens = d.inputTokens || 0
          root.outputTokens = d.outputTokens || 0
          root.cacheTokens = d.cacheTokens || 0
        } catch (e) {}
      }
    }
  }

  Timer {
    interval: 5 * 60 * 1000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  Text {
    id: label
    anchors.centerIn: parent
    textFormat: Text.PlainText
    text: "\u{ee0d} " + root.formatTokens(root.totalTokens)
    color: root.bar ? root.bar.barForeground : Color.foreground
    font.family: root.bar ? root.bar.fontFamily : Style.font.family
    font.pixelSize: Style.font.body
  }

  MouseArea {
    id: mouseArea
    anchors.fill: parent
    hoverEnabled: true
    onEntered: if (root.bar) root.bar.showTooltip(root,
      "Claude Code today: " + root.formatTokens(root.inputTokens) + " in / " +
      root.formatTokens(root.outputTokens) + " out / " +
      root.formatTokens(root.cacheTokens) + " cache\n" +
      "(local token counts, not plan-limit %)")
    onExited: if (root.bar) root.bar.hideTooltip(root)
  }
}

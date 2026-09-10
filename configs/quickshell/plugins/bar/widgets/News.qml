import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui

// New widget, not from omarchy-shell. Was flagged as blocked pending "which
// outlet + API key" — resolved by using NYT's free public RSS feed instead
// of a paid news API, since that needs no credentials at all.
BarWidget {
  id: root
  moduleName: "news"

  property var headlines: []

  implicitWidth: button.implicitWidth
  implicitHeight: barSize

  function refresh() {
    if (!newsProc.running) newsProc.running = true
  }

  Process {
    id: newsProc
    command: [Quickshell.env("HOME") + "/projects/arch-dotfiles/configs/quickshell/plugins/bar/widgets/news-headlines.sh"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try { root.headlines = JSON.parse(text || "[]") } catch (e) {}
      }
    }
  }

  Timer {
    interval: 30 * 60 * 1000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "\u{f1ea}"
    tooltipText: "News (NYT)"
    onEntered: { root.bar.hoverOpen(root.moduleName); root.refresh() }
    onExited: root.bar.hoverTriggerExit(root.moduleName)
  }

  HoverPanel {
    id: panel
    bar: root.bar
    moduleName: root.moduleName
    anchorWidget: root
    implicitWidth: Style.space(380) + Style.shadowOffset
    implicitHeight: content.implicitHeight + padding * 2 + Style.shadowOffset

    Column {
      id: content
      width: parent.width
      spacing: Style.spacing.md

      Text { text: "NYT Top Stories"; color: Color.menu.text; opacity: 0.6; font.pixelSize: Style.font.caption; font.family: Style.font.family }

      Repeater {
        model: root.headlines
        Text {
          required property string modelData
          width: content.width
          text: "• " + modelData
          color: Color.menu.text
          font.pixelSize: Style.font.body
          font.family: Style.font.family
          wrapMode: Text.Wrap
        }
      }

      Text {
        visible: root.headlines.length === 0
        text: "Loading…"
        color: Color.menu.text
        opacity: 0.5
        font.pixelSize: Style.font.body
        font.family: Style.font.family
      }
    }
  }
}

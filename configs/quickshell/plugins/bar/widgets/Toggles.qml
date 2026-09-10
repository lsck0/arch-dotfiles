import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// New widget, not from omarchy-shell. toggles/*.sh stay the only place
// toggle logic lives (toggles/menu.sh --fzf is the standing TUI, bound in
// tmux prefix+m) — this widget is a second consumer of the same backend.
// toggles/status.sh was toggles/waybar-status.sh until waybar was
// decommissioned 2026-09-01; it is a plain JSON status emitter now, and this
// widget is its only remaining caller. Used to shell out to `menu.sh`, which for its default (non-fzf)
// picker opens walker — a separate GUI window popping up from a bar click.
// Renders the same toggle list inline instead, via toggles-list.sh.
BarWidget {
  id: root
  moduleName: "toggles"

  readonly property string toggleDir: Quickshell.env("HOME") + "/projects/arch-dotfiles/toggles"
  readonly property string scriptDir: Quickshell.env("HOME") + "/projects/arch-dotfiles/configs/quickshell/plugins/bar/widgets"

  property string text: "⚙ 0"
  property string tooltip: ""
  property var items: []

  implicitWidth: label.implicitWidth + Style.spacing.controlPaddingX * 2
  implicitHeight: barSize

  Rectangle {
    anchors.fill: parent
    radius: Style.cornerRadius
    color: mouseArea.containsMouse ? Style.hoverFill : "transparent"
    Behavior on color { ColorAnimation { duration: 100 } }
  }

  function refresh() {
    if (!statusProc.running) statusProc.running = true
  }

  function refreshItems() {
    if (!itemsProc.running) itemsProc.running = true
  }

  function toggleItem(name) {
    Quickshell.execDetached([root.toggleDir + "/toggle-" + name + ".sh", "toggle"])
    Qt.callLater(function() { root.refresh(); root.refreshItems() })
  }

  Process {
    id: statusProc
    command: [root.toggleDir + "/status.sh"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var s = JSON.parse(text || "{}")
          root.text = s.text || "⚙ 0"
          root.tooltip = s.tooltip || ""
        } catch (e) {}
      }
    }
  }

  Process {
    id: itemsProc
    command: [root.scriptDir + "/toggles-list.sh"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try { root.items = JSON.parse(text || "[]") } catch (e) {}
      }
    }
  }

  // Was 5000ms. This poll is a catch-up for out-of-band changes only --
  // refresh() already fires immediately after every in-panel toggle (see
  // Qt.callLater(root.refresh) at the call site) -- so a toggle flipped
  // from outside quickshell (another keybind, a script) just takes longer
  // to show up here. 20s keeps that lag imperceptible in practice while
  // cutting status.sh's ~40-process cost by 4x. See research/ROADMAP.md's "Post-Phase-8" note for the
  // interval choices and why FileView push updates were rejected.
  Timer {
    interval: 20000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  Text {
    id: label
    anchors.centerIn: parent
    textFormat: Text.PlainText
    text: root.text
    color: root.bar ? root.bar.barForeground : Color.foreground
    font.family: root.bar ? root.bar.fontFamily : Style.font.family
    font.pixelSize: Style.font.body
  }

  MouseArea {
    id: mouseArea
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onEntered: { root.bar.hoverOpen(root.moduleName); root.refreshItems() }
    onExited: root.bar.hoverTriggerExit(root.moduleName)
  }

  HoverPanel {
    id: panel
    bar: root.bar
    moduleName: root.moduleName
    anchorWidget: root
    implicitWidth: Style.space(260) + Style.shadowOffset
    implicitHeight: Math.min(Style.space(400), content.implicitHeight + padding * 2) + Style.shadowOffset

    Flickable {
      anchors.fill: parent
      contentHeight: content.implicitHeight
      clip: true

      Column {
        id: content
        width: parent.width
        spacing: Style.spacing.xs

        // Ui/Toggle.qml floors each row at 54px — ten toggles is ~540px,
        // taller than most screens want popping open on hover. The
        // Flickable above caps the panel at 400px and scrolls the rest,
        // same pattern Notifications.qml uses for its history list.
        Repeater {
          model: root.items
          Toggle {
            required property var modelData
            width: content.width
            label: modelData.label
            checked: modelData.on
            titleSize: Style.font.body
            onClicked: root.toggleItem(modelData.name)
          }
        }

        Text {
          visible: root.items.length === 0
          text: "Loading…"
          color: Color.menu.text
          opacity: 0.5
          font.pixelSize: Style.font.body
          font.family: Style.font.family
        }
      }
    }
  }
}

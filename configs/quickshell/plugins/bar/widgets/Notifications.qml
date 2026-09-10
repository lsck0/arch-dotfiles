import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "../../notifications/components"

// New widget, not from omarchy-shell. Originally bridged mako (the "New
// widget... — mako already handles the actual notification daemon duties"
// comment below described that design); now bridges
// plugins/notifications/Service.qml, the native daemon that replaced mako
// (see TODO.md for the keep-vs-replace decision). History is read straight
// off Service.qml's own history directory (the same files the daemon reads
// on restore/replay) rather than through a new IPC method — no method for
// "dump history as JSON" exists upstream either, only `showHistory` (replay
// as toasts), and this repo's shape needs a flat list for the panel, not a
// replay.
BarWidget {
  id: root
  moduleName: "notifications"

  readonly property string toggleScript: Quickshell.env("HOME") + "/projects/arch-dotfiles/toggles/toggle-dnd.sh"
  readonly property string quickshellConfigPath: Quickshell.env("HOME") + "/.config/quickshell"
  readonly property string historyDir: Quickshell.env("HOME") + "/.local/state/quickshell/notifications/history"

  property bool dndOn: false
  property var history: []

  implicitWidth: button.implicitWidth
  implicitHeight: barSize

  function refreshDnd() {
    if (!dndProc.running) dndProc.running = true
  }

  function refreshHistory() {
    if (!historyProc.running) historyProc.running = true
  }

  // Open whatever a history entry points at. Two tiers, because a stored
  // entry is not a live notification any more — its D-Bus action object is
  // long gone, so `execArgv` (which the daemon persists precisely so
  // restored toasts stay clickable) is the only real action carrier.
  // Falling back to the app's desktop entry means clicking a notification
  // from, say, Discord still opens Discord.
  // Last-resort matcher. A notification's app_name is a display name, and
  // neither byId nor heuristicLookup reliably bridges "ghostty" to
  // `com.mitchellh.ghostty.desktop`. Match case-insensitively on the entry
  // name, the id, or the id's last dotted segment, which covers the
  // reverse-DNS ids most modern apps ship.
  function findEntry(name) {
    var want = String(name || "").trim().toLowerCase()
    if (!want) return null
    var list = DesktopEntries.applications.values || []
    for (var i = 0; i < list.length; i++) {
      var e = list[i]
      if (!e) continue
      var id = String(e.id || "").toLowerCase()
      var nm = String(e.name || "").toLowerCase()
      if (nm === want || id === want) return e
      var tail = id.indexOf(".") >= 0 ? id.substring(id.lastIndexOf(".") + 1) : id
      if (tail === want) return e
    }
    return null
  }

  function openEntry(entry) {
    if (!entry) return
    var argv = null
    try {
      var parsed = JSON.parse(String(entry.execArgv || ""))
      if (Array.isArray(parsed) && parsed.length > 0) argv = parsed
    } catch (e) {}
    if (argv) {
      Quickshell.execDetached(argv)
      if (root.bar) root.bar.closePanel(root.moduleName)
      return
    }
    // byId wants an actual desktop-file id; the notification's app_name is
    // a display name ("Discord", "Firefox"), so heuristicLookup is the one
    // that usually matches. Try both, appIcon first since it is more often
    // a real id.
    var candidates = [entry.appIcon, entry.app]
    for (var i = 0; i < candidates.length; i++) {
      var id = String(candidates[i] || "").trim()
      if (!id) continue
      var de = DesktopEntries.byId(id) || DesktopEntries.heuristicLookup(id) || root.findEntry(id)
      if (de) {
        de.execute()
        if (root.bar) root.bar.closePanel(root.moduleName)
        return
      }
    }
    // Nothing to open — a shell-generated notification with no action.
    // Deliberately a no-op rather than a guess.
  }

  function toggleDnd() {
    Quickshell.execDetached([root.toggleScript, "toggle"])
    Qt.callLater(root.refreshDnd)
  }

  function dismissAll() {
    Quickshell.execDetached(["quickshell", "ipc", "-p", root.quickshellConfigPath, "call", "notifications", "clear"])
    Qt.callLater(root.refreshHistory)
  }

  Process {
    id: dndProc
    command: [root.toggleScript, "get"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.dndOn = String(text || "").trim() === "on"
    }
  }

  Process {
    id: historyProc
    command: ["bash", "-c", "awk 1 \"$1\"/*.json 2>/dev/null | jq -s -c 'sort_by(-.timestamp)'", "--", root.historyDir]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try { root.history = JSON.parse(text || "[]") } catch (e) {}
      }
    }
  }

  Timer {
    interval: 10000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refreshDnd()
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.dndOn ? "\u{f1f6}" : "\u{f0f3}"
    active: root.history.length > 0 && !root.dndOn
    tooltipText: root.dndOn ? "Do Not Disturb (on)" : root.history.length + " recent notifications"
    onPressed: function(b) {
      if (b === Qt.MiddleButton) root.toggleDnd()
    }
    onEntered: { root.bar.hoverOpen(root.moduleName); root.refreshHistory() }
    onExited: root.bar.hoverTriggerExit(root.moduleName)
  }

  HoverPanel {
    id: panel
    bar: root.bar
    moduleName: root.moduleName
    anchorWidget: root
    implicitWidth: Style.space(340) + Style.shadowOffset
    implicitHeight: Math.min(Style.space(400), content.implicitHeight + padding * 2) + Style.shadowOffset

    Flickable {
      anchors.fill: parent
      contentHeight: content.implicitHeight
      clip: true

      Column {
        id: content
        width: parent.width
        spacing: Style.spacing.md

        Row {
          width: parent.width
          Text {
            text: root.dndOn ? "Do Not Disturb: on" : "Notifications"
            color: Color.menu.text
            font.pixelSize: Style.font.title
            font.family: Style.font.family
            width: parent.width - clearLabel.implicitWidth
          }
          Text {
            id: clearLabel
            text: "Clear"
            color: Color.accent
            font.pixelSize: Style.font.bodySmall
            font.family: Style.font.family
            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: { root.dismissAll(); root.bar.closePanel(root.moduleName) }
            }
          }
        }

        Toggle {
          width: parent.width
          label: "Do Not Disturb"
          description: "Silence new notification popups"
          checked: root.dndOn
          onClicked: root.toggleDnd()
        }

        PanelSeparator {}

        Text {
          visible: root.history.length === 0
          text: "Nothing recent"
          color: Color.menu.text
          opacity: 0.6
          font.pixelSize: Style.font.body
          font.family: Style.font.family
        }

        // Rendered with the SAME NotificationCard the toasts use, rather
        // than the two plain Texts that used to live here. The card already
        // does everything the SPEC asks of this list — an image slot with
        // app-icon and glyph fallbacks, urgency colouring, and a click
        // action — and the stored history rows were verified to retain
        // every field it needs (app, appIcon, image, glyph, execArgv,
        // urgency, timestamp). Nothing had to change in the daemon.
        Repeater {
          model: root.history
          delegate: NotificationCard {
            required property var modelData
            width: content.width
            app: modelData.app || ""
            appIcon: modelData.appIcon || ""
            summary: modelData.summary || ""
            body: modelData.body || ""
            image: modelData.image || ""
            glyph: modelData.glyph || ""
            urgency: modelData.urgency !== undefined ? modelData.urgency : 1
            timestamp: modelData.timestamp || 0
            cornerRadius: Style.cornerRadius

            onCardClicked: root.openEntry(modelData)
            // The daemon owns the history files, so removing one entry from
            // the panel would desync it. Clicking the close affordance
            // clears the whole history, which is the only operation the
            // service actually exposes.
            onCloseRequested: root.dismissAll()
          }
        }
      }
    }
  }
}

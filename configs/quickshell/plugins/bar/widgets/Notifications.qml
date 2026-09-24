import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "../../notifications/components"

// New widget, not from omarchy-shell.
BarWidget {
  id: root
  moduleName: "notifications"

  readonly property string toggleScript: Paths.toggle("toggle-dnd.sh")
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

  // Open whatever a history entry points at.
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
    // byId wants an actual desktop-file id; the notification's app_name is a display name ("Discord", "Firefox"), so heuristicLookup is the one that usually matches.
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
  }

  function toggleDnd() {
    // A real child Process, not execDetached + Qt.callLater.
    if (toggleProc.running) return
    toggleProc.running = true
  }

  Process {
    id: toggleProc
    command: [root.toggleScript, "toggle"]
    running: false
    onExited: root.refreshDnd()
  }

  function dismissAll() {
    Quickshell.execDetached(Paths.ipcCall("notifications", "clear"))
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
    onEntered: root.bar.hoverOpen(root.moduleName)
    onExited: root.bar.hoverTriggerExit(root.moduleName)
  }

  HoverPanel {
    id: panel
    bar: root.bar
    moduleName: root.moduleName
    anchorWidget: root
    implicitWidth: Style.panelWidth.normal + Style.shadowOffset
    implicitHeight: Math.min(Style.space(400), content.implicitHeight + padding * 2) + Style.shadowOffset

    onOpened: root.refreshHistory()

    // And keep it current while it stays open: a notification arriving with the panel already up should appear in the list, not wait for the next hover.
    Timer {
      interval: 4000
      running: panel.visible
      repeat: true
      onTriggered: root.refreshHistory()
    }

    // One clock for the whole list.
    property double nowMs: Date.now()
    Timer {
      interval: 30000
      running: panel.visible
      repeat: true
      triggeredOnStart: true
      onTriggered: panel.nowMs = Date.now()
    }

    Flickable {
      id: historyFlick
      anchors.fill: parent
      // contentWidth + VerticalFlick, matching Tray's menu Flickable: without them contentWidth defaults to -1 and a horizontal drag slides the whole list sideways with nothing to scroll to.
      contentWidth: width
      contentHeight: content.implicitHeight
      flickableDirection: Flickable.VerticalFlick
      interactive: contentHeight > height
      clip: true
      boundsBehavior: Flickable.StopAtBounds

      Column {
        id: content
        width: parent.width
        // Rows sit closer together than the panel's own sections do: with the borders gone they read as one list, and section spacing between them pulled them back apart into separate things.
        spacing: Style.spacing.xs

        // Same section header as every other panel; the toggle below already says DND state.
        Item {
          width: parent.width
          implicitHeight: Math.max(notifHeader.implicitHeight, clearLabel.implicitHeight)
          PanelSectionHeader {
            id: notifHeader
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: "NOTIFICATIONS" + (root.history.length > 0 ? " · " + root.history.length : "")
          }
          Text {
            id: clearLabel
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            visible: root.history.length > 0
            text: "Clear"
            color: Color.accent
            font.pixelSize: Style.font.caption
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
          // Borderless like every other row in this panel; the switch itself carries the affordance.
          borderSpec: Border.flat("transparent", 0)
        }

        PanelSeparator {}

        Text {
          visible: root.history.length === 0
          text: "Nothing recent"
          color: Color.menu.text
          opacity: Style.emphasis.dim
          font.pixelSize: Style.font.body
          font.family: Style.font.family
        }

        // Rendered with the SAME NotificationCard the toasts use, rather than the two plain Texts that used to live here.
        Repeater {
          model: root.history
          delegate: NotificationCard {
            required property var modelData
            // A row, not a toast — see NotificationCard's `variant`.
            variant: "row"
            now: panel.nowMs
            // A short history is a detail view, not a list: with one or two entries there is nothing to scan past, so show the message instead of eliding it into "…in the…" above 40px of empty panel.
            bodyLines: root.history.length <= 2 ? 10 : 3
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
            // The daemon owns the history files, so removing one entry from the panel would desync it.
            onCloseRequested: root.dismissAll()
          }
        }
      }
    }

    // The list is clipped mid-row when there is more history than panel, with nothing to say so — it just looked like a rendering cut.
    Rectangle {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      height: Style.space(24)
      visible: historyFlick.contentHeight > historyFlick.height + 1
      opacity: historyFlick.atYEnd ? 0 : 1
      Behavior on opacity { NumberAnimation { duration: 140 } }
      gradient: Gradient {
        GradientStop { position: 0.0; color: Util.alpha(Color.menu.background, 0.0) }
        GradientStop { position: 1.0; color: Util.alpha(Color.menu.background, 0.95) }
      }
    }
  }
}

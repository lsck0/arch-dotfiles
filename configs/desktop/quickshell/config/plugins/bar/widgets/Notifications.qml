pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "../../notifications/components"
import "../../notifications/NotificationLogic.js" as NotificationLogic

BarWidget {
  id: root
  moduleName: "notifications"
  barPriority: 65
  hoverPanel: true
  hoverFill: true

  readonly property var service: root.bar && root.bar.shellHost
    ? root.bar.shellHost.plugin("service.notifications") : null
  readonly property bool dndOn: service ? service.doNotDisturb : false
  // what switched it on when it was not the user: "OBS", "screen share", else ""
  readonly property string dndSource: service && service.dndSource ? service.dndSource : ""
  readonly property var history: service ? service.history : []
  readonly property double seenMs: service ? service.historySeenMs : 0
  readonly property int unseenCount: history.filter(function(e) { return (e.timestamp || 0) > root.seenMs }).length

  // a history card shows bodyLinesCollapsed lines; one card at a time opens to bodyLinesExpanded
  readonly property int bodyLinesCollapsed: 3
  readonly property int bodyLinesExpanded: 30
  property string expandedKey: ""

  implicitWidth: button.implicitWidth

  function findEntry(name) {
    var want = String(name || "").trim().toLowerCase()
    if (!want) return null
    var list = DesktopEntries.applications.values || []
    for (let i = 0; i < list.length; i++) {
      let e = list[i]
      if (!e) continue
      let id = String(e.id || "").toLowerCase()
      let nm = String(e.name || "").toLowerCase()
      if (nm === want || id === want) return e
      let tail = id.indexOf(".") >= 0 ? id.substring(id.lastIndexOf(".") + 1) : id
      if (tail === want) return e
    }
    return null
  }

  function openEntry(entry) {
    if (!entry) return
    var argv = NotificationLogic.parseExecArgv(entry.execArgv)
    var candidates = [entry.appIcon, entry.app]
    for (let i = 0; !argv && i < candidates.length; i++) {
      let id = String(candidates[i] || "").trim()
      if (!id) continue
      let de = DesktopEntries.byId(id) || DesktopEntries.heuristicLookup(id) || root.findEntry(id)
      if (de) argv = ["gtk-launch", de.id + ".desktop"]
    }
    if (!argv) return
    Quickshell.execDetached(["uwsm-app", "--"].concat(argv))
    root.closePanel()
  }

  function toggleDnd() {
    if (root.service) root.service.setDoNotDisturb(!root.service.doNotDisturb)
  }

  function clearHistory() {
    if (root.service) root.service.clearHistory()
  }

  function removeEntry(entry) {
    if (root.service) root.service.removeEntry(entry.originalId || 0, entry.timestamp || 0)
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.dndOn
      ? (root.unseenCount > 0 ? "\u{ec09}" : "\u{ec08}")
      : (root.unseenCount > 0 ? "\u{eb9a}" : "\u{eaa2}")
    useActiveColor: false
    tooltipText: (root.dndOn ? "Do not disturb :: " : "") + (root.unseenCount > 0 ? root.unseenCount + " new :: " : "")
      + Util.count(root.history.length, "recent notification") + " :: MMB dnd"
    onPressed: function(b) {
      if (b === Qt.MiddleButton) root.toggleDnd()
    }
  }

  HoverPanel {
    id: panel
    anchorWidget: root
    title: "NOTIFICATIONS"
    implicitWidth: Style.panelWidth.normal
    maxBodyHeight: Style.space(400)

    onOpened: if (root.service) root.service.refreshHistory()
    // seen once the panel closes again: while it is open the new ones are on screen
    onShownChanged: if (!shown) { if (root.service) root.service.historyMarkSeen(); root.expandedKey = "" }

    property double nowMs: Date.now()
    Timer {
      interval: 30000
      running: panel.visible
      repeat: true
      triggeredOnStart: true
      onTriggered: panel.nowMs = Date.now()
    }

    Column {
      id: content
      width: parent.width
      spacing: Style.spacing.xs

      PanelRow {
        width: parent.width
        label: "Do not disturb"
        trailing: root.dndOn && root.dndSource !== "" ? "on :: " + root.dndSource : ""
        stateMarker: true
        on: root.dndOn
        onActivated: root.toggleDnd()
      }

      PanelSeparator {}

      Item {
        width: parent.width
        implicitHeight: Math.max(notifHeader.implicitHeight, clearButton.implicitHeight)
        PanelSectionHeader {
          id: notifHeader
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          text: "HISTORY" + (root.history.length > 0 ? " :: " + root.history.length : "")
        }
        // a control in the panel's focus chain, so the keyboard reaches it too
        Button {
          id: clearButton
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          visible: root.history.length > 0
          variant: "chip"
          focusable: true
          text: "CLEAR"
          onClicked: { root.clearHistory(); root.closePanel() }
        }
      }

      Label {
        visible: root.history.length === 0
        text: "> NO NOTIFICATIONS"
        dim: true
        caption: true
      }

      Repeater {
        model: root.history
        delegate: Column {
          id: entry
          required property var modelData
          readonly property string key: (modelData.originalId || 0) + ":" + (modelData.timestamp || 0)
          readonly property bool expanded: root.expandedKey === key
          // an opened card no longer cuts its body, and still needs its LESS
          readonly property bool bodyLong: card.truncated || expanded

          function toggleExpanded() { root.expandedKey = expanded ? "" : key }

          width: content.width

          NotificationCard {
            id: card
            variant: "row"
            now: panel.nowMs
            bodyLines: entry.expanded ? root.bodyLinesExpanded : root.bodyLinesCollapsed
            width: parent.width
            app: entry.modelData.app || ""
            appIcon: entry.modelData.appIcon || ""
            summary: entry.modelData.summary || ""
            body: entry.modelData.body || ""
            image: entry.modelData.image || ""
            glyph: entry.modelData.glyph || ""
            urgency: entry.modelData.urgency !== undefined ? entry.modelData.urgency : 1
            timestamp: entry.modelData.timestamp || 0

            Keys.onSpacePressed: if (entry.bodyLong) entry.toggleExpanded()
            onCardClicked: root.openEntry(entry.modelData)
            onCloseRequested: root.removeEntry(entry.modelData)
          }

          Button {
            visible: entry.bodyLong
            anchors.right: parent.right
            variant: "chip"
            text: entry.expanded ? "LESS" : "MORE"
            onClicked: entry.toggleExpanded()
          }
        }
      }
    }
  }
}

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "../../notifications/components"

BarWidget {
  id: root
  moduleName: "notifications"

  readonly property QtObject service: root.bar && root.bar.shellHost
    ? root.bar.shellHost.serviceFor("service.notifications") : null
  readonly property string historyDir: service ? service.historyDir : ""

  readonly property bool dndOn: service ? service.doNotDisturb : false
  property var history: []

  implicitWidth: button.implicitWidth
  implicitHeight: barSize

  function refreshHistory() {
    if (root.historyDir && !historyProc.running) historyProc.running = true
  }

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
    // app_name is a display name, so heuristicLookup usually matches
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
  }

  function toggleDnd() {
    if (root.service) root.service.setDoNotDisturb(!root.service.doNotDisturb)
  }

  function clearHistory() {
    if (!root.service) return
    root.service.clearHistory()
    // the delete is queued, a re-read now could resurrect the rows
    root.history = []
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
    onEntered: if (root.bar) root.bar.hoverOpen(root.moduleName)
    onExited: if (root.bar) root.bar.hoverTriggerExit(root.moduleName)
  }

  HoverPanel {
    id: panel
    bar: root.bar
    moduleName: root.moduleName
    anchorWidget: root
    title: "NOTIFICATIONS"
    implicitWidth: Style.panelWidth.normal
    implicitHeight: Math.min(Style.space(400), content.implicitHeight + padding * 2 + titleInset)

    onOpened: root.refreshHistory()

    // keep the list current while open
    Timer {
      interval: 4000
      running: panel.visible
      repeat: true
      onTriggered: root.refreshHistory()
    }

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
      // without contentWidth a horizontal drag slides the list
      contentWidth: width
      contentHeight: content.implicitHeight
      flickableDirection: Flickable.VerticalFlick
      interactive: contentHeight > height
      clip: true
      boundsBehavior: Flickable.StopAtBounds

      Column {
        id: content
        width: parent.width
        spacing: Style.spacing.xs

        Item {
          width: parent.width
          implicitHeight: Math.max(notifHeader.implicitHeight, clearLabel.implicitHeight)
          PanelSectionHeader {
            id: notifHeader
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: "HISTORY" + (root.history.length > 0 ? " :: " + root.history.length : "")
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
              onClicked: { root.clearHistory(); if (root.bar) root.bar.closePanel(root.moduleName) }
            }
          }
        }

        Toggle {
          width: parent.width
          label: "Do Not Disturb"
          description: "Silence new notification popups"
          checked: root.dndOn
          onClicked: root.toggleDnd()
          borderSpec: Border.flat("transparent", 0)
        }

        PanelSeparator {}

        Text {
          visible: root.history.length === 0
          text: "> NOTHING RECENT"
          color: Color.menu.text
          opacity: Style.emphasis.dim
          font.pixelSize: Style.font.body
          font.family: Style.font.family
          font.letterSpacing: Style.displayTracking
        }

        Repeater {
          model: root.history
          delegate: NotificationCard {
            required property var modelData
            variant: "row"
            now: panel.nowMs
            // few entries: show the full body
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

            onCardClicked: root.openEntry(modelData)
            // the daemon owns history, so clear all
            onCloseRequested: root.clearHistory()
          }
        }
      }
    }

    // fade hints at clipped rows
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

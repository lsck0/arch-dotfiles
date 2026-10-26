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
  hoverPanel: true

  readonly property var service: root.bar && root.bar.shellHost
    ? root.bar.shellHost.plugin("service.notifications") : null
  readonly property bool dndOn: service ? service.doNotDisturb : false
  readonly property var history: service ? service.history : []

  implicitWidth: button.implicitWidth
  implicitHeight: barSize

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
    if (argv) {
      Quickshell.execDetached(["uwsm-app", "--"].concat(argv))
      if (root.bar) root.bar.closePanel(root.moduleName)
      return
    }
    var candidates = [entry.appIcon, entry.app]
    for (let i = 0; i < candidates.length; i++) {
      let id = String(candidates[i] || "").trim()
      if (!id) continue
      let de = DesktopEntries.byId(id) || DesktopEntries.heuristicLookup(id) || root.findEntry(id)
      if (de) {
        Quickshell.execDetached(["uwsm-app", "--", "gtk-launch", de.id + ".desktop"])
        if (root.bar) root.bar.closePanel(root.moduleName)
        return
      }
    }
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
      ? (root.history.length > 0 ? "\u{ec09}" : "\u{ec08}")
      : (root.history.length > 0 ? "\u{eb9a}" : "\u{eaa2}")
    useActiveColor: false
    tooltipText: (root.dndOn ? "Do not disturb :: " : "") + root.history.length + " recent notifications"
    onPressed: function(b) {
      if (b === Qt.MiddleButton) root.toggleDnd()
    }
  }

  HoverPanel {
    id: panel
    anchorWidget: root
    title: "NOTIFICATIONS"
    implicitWidth: Style.panelWidth.normal
    implicitHeight: Math.min(Style.space(400), content.implicitHeight + padding * 2 + titleInset + Style.fx.bracketWidth)

    onOpened: if (root.service) root.service.refreshHistory()

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

        PanelRow {
          width: parent.width
          label: "Do not disturb"
          trailing: "silence popups"
          stateMarker: true
          on: root.dndOn
          onActivated: root.toggleDnd()
        }

        PanelSeparator {}

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
            color: Colors.accent
            font.pixelSize: Style.font.caption
            font.family: Style.font.family
            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: { root.clearHistory(); if (root.bar) root.bar.closePanel(root.moduleName) }
            }
          }
        }

        Text {
          visible: root.history.length === 0
          bottomPadding: Style.spacing.md
          text: "> NOTHING RECENT"
          color: Colors.menu.text
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
            onCloseRequested: root.removeEntry(modelData)
          }
        }
      }
    }

    Rectangle {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      height: Style.space(24)
      visible: historyFlick.contentHeight > historyFlick.height + 1
      opacity: historyFlick.atYEnd ? 0 : 1
      Behavior on opacity { NumberAnimation { duration: Style.motion.base; easing.type: Easing.BezierSpline; easing.bezierCurve: Style.motion.enter } }
      gradient: Gradient {
        GradientStop { position: 0.0; color: Util.alpha(Colors.menu.background, 0.0) }
        GradientStop { position: 1.0; color: Util.alpha(Colors.menu.background, 0.95) }
      }
    }
  }
}

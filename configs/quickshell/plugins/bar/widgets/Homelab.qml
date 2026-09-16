import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Homelab health from homelab-status.py, which derives the fleet and every link
// from the homelab source. Every row in the panel opens the thing it describes.
BarWidget {
  id: root
  moduleName: "homelab"

  property bool received: false
  property bool ok: false
  // "source" when the homelab checkout is missing or unreadable, else a network failure.
  property string error: ""
  property var links: ({ homepage: "", grafana: "", dashboard: "", alerts: "", proxmox: "", nas: "" })
  property var services: []
  property var alerts: []
  property var host: ({})
  property var storage: ({})
  property var traffic: ({})

  // Link-only entries (up === null) have no state and are left out of the counts.
  readonly property var monitored: services.filter(function(s) { return s.up === true || s.up === false })
  readonly property var downServices: monitored.filter(function(s) { return !s.up && !s.onDemand })
  readonly property int upCount: monitored.filter(function(s) { return s.up }).length
  readonly property int asleepCount: monitored.filter(function(s) { return !s.up && s.onDemand }).length
  readonly property int problemCount: alerts.length + downServices.length
  // Nightly backups; a day and a bit without one means one was missed.
  readonly property bool backupStale: storage.backupAgeMin === null || storage.backupAgeMin === undefined
    || storage.backupAgeMin > 26 * 60

  function open(url) {
    if (!url) return
    Quickshell.execDetached(["xdg-open", url])
    if (root.bar) root.bar.closePanel(root.moduleName)
  }

  function ago(minutes) {
    var m = Math.max(0, Math.round(Number(minutes) || 0))
    if (m < 60) return m + "m ago"
    if (m < 2880) return Math.floor(m / 60) + "h ago"
    return Math.floor(m / 1440) + "d ago"
  }

  function num(value, suffix) {
    return value === null || value === undefined ? "–" : value + (suffix || "")
  }

  implicitWidth: trigger.implicitWidth + Style.bar.itemPaddingX * 2
  implicitHeight: barSize

  Process {
    id: statusProc
    running: true
    command: [Paths.barWidget("homelab-status.py")]
    stdout: SplitParser {
      splitMarker: "\n"
      onRead: function(line) {
        if (!line) return
        try {
          var s = JSON.parse(line)
          root.received = true
          root.ok = s.ok === true
          root.error = s.error || ""
          if (!root.ok) return
          if (s.links) root.links = s.links
          root.services = s.services || []
          root.alerts = s.alerts || []
          root.host = s.host || {}
          root.storage = s.storage || {}
          root.traffic = s.traffic || {}
        } catch (e) {}
      }
    }
  }

  Rectangle {
    anchors.fill: parent
    radius: Style.cornerRadius
    color: mouseArea.containsMouse ? Style.hoverFill : "transparent"
    Behavior on color { ColorAnimation { duration: 100 } }
  }

  Row {
    id: trigger
    anchors.centerIn: parent
    spacing: Style.spacing.sm

    Text {
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      // md-server_network / md-server_network_off
      text: root.ok || !root.received ? "\u{f048d}" : "\u{f048e}"
      color: root.ok && root.problemCount > 0 ? Color.urgent
        : root.bar ? root.bar.barForeground : Color.foreground
      opacity: root.ok && root.problemCount > 0 ? 1 : Style.emphasis.dim
      font.family: root.bar ? root.bar.iconFontFamily : Style.font.iconFamily
      font.pixelSize: Style.font.icon
    }
    Text {
      anchors.verticalCenter: parent.verticalCenter
      visible: root.ok && root.problemCount > 0
      textFormat: Text.PlainText
      text: root.problemCount
      color: Color.urgent
      font.family: root.bar ? root.bar.fontFamily : Style.font.family
      font.pixelSize: Style.font.body
    }
  }

  MouseArea {
    id: mouseArea
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onEntered: if (root.bar) root.bar.hoverOpen(root.moduleName)
    onExited: if (root.bar) root.bar.hoverTriggerExit(root.moduleName)
    onClicked: root.open(root.links.homepage)
  }

  // System.qml's label/value row, clickable: the hover fill bleeds past the
  // column edge so the text stays aligned with the section headers.
  component Row_: Item {
    id: kv
    property string label: ""
    property string value: ""
    property string url: ""
    property bool alert: false
    // Side information, drawn muted after the value.
    property string note: ""
    width: parent.width
    implicitHeight: valueText.implicitHeight + Style.spacing.xxs * 2

    Rectangle {
      anchors.fill: parent
      anchors.leftMargin: -Style.spacing.sm
      anchors.rightMargin: -Style.spacing.sm
      radius: Style.cornerRadius
      color: kvMouse.containsMouse && kv.url ? Style.hoverFill : "transparent"
      Behavior on color { ColorAnimation { duration: 100 } }
    }
    Text {
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      width: parent.width * 0.4
      text: kv.label
      color: Color.menu.text
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      elide: Text.ElideRight
    }
    Row {
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.spacing.sm
      Text {
        id: valueText
        text: kv.value
        color: kv.alert ? Color.urgent : Color.menu.text
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
      }
      Text {
        visible: kv.note !== ""
        text: kv.note
        color: Color.menu.text
        opacity: Style.emphasis.faint
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
      }
    }
    MouseArea {
      id: kvMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: kv.url ? Qt.PointingHandCursor : Qt.ArrowCursor
      onClicked: root.open(kv.url)
    }
  }

  // One titled grid of services. Three columns fit the wide panel without
  // eliding the longer VM names.
  component ServiceGroup: Column {
    id: groupBox
    property string title: ""
    property string group: ""
    readonly property var members: root.services.filter(function(s) { return s.group === groupBox.group })
    width: parent.width
    visible: members.length > 0
    spacing: Style.spacing.xs

    Text {
      text: groupBox.title
      color: Color.accent
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
    }

    Grid {
      id: serviceGrid
      width: parent.width
      columns: 3
      columnSpacing: Style.spacing.lg

      Repeater {
        model: groupBox.members
        delegate: Item {
          id: tile
          required property var modelData
          readonly property bool asleep: modelData.up === false && modelData.onDemand
          readonly property bool down: modelData.up === false && !modelData.onDemand
          width: (serviceGrid.width - serviceGrid.columnSpacing * (serviceGrid.columns - 1)) / serviceGrid.columns
          height: Style.row.control

          Rectangle {
            anchors.fill: parent
            anchors.leftMargin: -Style.spacing.sm
            radius: Style.cornerRadius
            color: tileMouse.containsMouse && tile.modelData.url ? Style.hoverFill : "transparent"
            Behavior on color { ColorAnimation { duration: 100 } }
          }
          Row {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.spacing.sm

            // ● up or link-only (never checked), ○ asleep, red when down.
            Text {
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: tile.asleep ? "○" : "●"
              color: tile.down ? Color.urgent : Color.menu.text
              opacity: tile.asleep ? Style.emphasis.faint : 1
              font.family: Style.font.family
              font.pixelSize: Style.font.body
            }
            Text {
              anchors.verticalCenter: parent.verticalCenter
              width: tile.width - Style.spacing.sm - Style.font.body
              textFormat: Text.PlainText
              text: tile.modelData.name
              elide: Text.ElideRight
              color: tile.down ? Color.urgent : Color.menu.text
              opacity: tile.asleep ? Style.emphasis.faint : 1
              font.family: Style.font.family
              font.pixelSize: Style.font.body
            }
          }
          MouseArea {
            id: tileMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: tile.modelData.url ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: root.open(tile.modelData.url)
          }
        }
      }
    }
  }

  HoverPanel {
    id: panel
    bar: root.bar
    moduleName: root.moduleName
    anchorWidget: root
    implicitWidth: Style.panelWidth.wide + Style.shadowOffset
    implicitHeight: content.implicitHeight + padding * 2 + Style.shadowOffset

    Column {
      id: content
      width: parent.width
      spacing: Style.spacing.md

      PanelSectionHeader { text: "Homelab"; fontSize: Style.font.title }

      // ---- unreachable ------------------------------------------------------
      Row_ {
        visible: !root.ok
        label: "Status"
        value: !root.received ? "Connecting…" : root.error === "source" ? "No homelab checkout" : "Unreachable"
        alert: root.received
      }
      PanelSeparator { visible: root.received && !root.ok && root.error !== "source" }
      PanelSectionHeader { text: "Tools"; visible: root.received && !root.ok && root.error !== "source" }
      // Off the LAN the monitoring VM is only reachable through WireGuard.
      PanelRow {
        width: parent.width
        visible: root.received && !root.ok && root.error !== "source"
        glyph: "\u{f0582}"   // md-vpn
        label: "Connect homelab VPN"
        onActivated: {
          Quickshell.execDetached([Paths.toggle("toggle-vpn.sh"), "on"])
          if (root.bar) root.bar.closePanel(root.moduleName)
        }
      }

      Column {
        width: parent.width
        visible: root.ok
        spacing: Style.spacing.md

        // ---- alerts ---------------------------------------------------------
        Column {
          width: parent.width
          visible: root.alerts.length > 0
          spacing: Style.spacing.md

          PanelSectionHeader { text: "Alerts"; foreground: Color.urgent }
          Repeater {
            model: root.alerts
            delegate: Row_ {
              required property var modelData
              label: modelData.target || modelData.name
              value: modelData.target ? modelData.name : ""
              note: root.ago(modelData.minutes)
              url: root.links.alerts
              alert: true
            }
          }
          PanelSeparator {}
        }

        // ---- host -----------------------------------------------------------
        PanelSectionHeader { text: "Host" }
        Row_ { label: "Usage"; value: root.num(root.host.cpuPct, "%"); url: root.links.proxmox }
        Row_ {
          label: "Memory"
          value: root.num(root.host.memUsedGb) + " / " + root.num(root.host.memTotalGb, " GB")
          url: root.links.proxmox
        }
        Row_ { label: "Temperature"; value: root.num(root.host.tempC, "°C"); url: root.links.proxmox }
        Row_ { label: "Uptime"; value: root.num(root.host.uptimeH, " h"); url: root.links.proxmox }

        // ---- storage --------------------------------------------------------
        PanelSeparator {}
        PanelSectionHeader { text: "Storage" }
        Row_ {
          label: "NAS free"
          value: root.num(root.storage.nasFreeGb) + " / " + root.num(root.storage.nasTotalGb, " GB")
          url: root.links.nas
        }
        Row_ {
          label: "Disks"
          value: root.num(root.storage.disksHealthy) + " / " + root.num(root.storage.disksTotal, " healthy")
          alert: root.storage.disksHealthy < root.storage.disksTotal
          url: root.links.dashboard
        }
        Row_ { label: "NVMe wear"; value: root.num(root.storage.nvmeWearPct, "%"); url: root.links.dashboard }
        Row_ {
          label: "Last backup"
          value: root.storage.backupAgeMin === null || root.storage.backupAgeMin === undefined
            ? "never" : root.ago(root.storage.backupAgeMin)
          alert: root.backupStale
          url: root.links.nas
        }

        // ---- traffic --------------------------------------------------------
        PanelSeparator {}
        PanelSectionHeader { text: "Traffic" }
        Row_ { label: "Internal"; value: root.num(root.traffic.internalRps, " req/s"); url: root.links.dashboard }
        Row_ { label: "Public"; value: root.num(root.traffic.externalRps, " req/s"); url: root.links.dashboard }
        Row_ {
          label: "Server errors"
          value: root.num(root.traffic.errorRps, " req/s")
          alert: root.traffic.errorRps > 0
          url: root.links.dashboard
        }

        // ---- services -------------------------------------------------------
        PanelSeparator {}
        PanelSectionHeader { text: "Services" }
        Row_ {
          label: "Up"
          value: root.upCount + " / " + root.monitored.length
          url: root.links.homepage
        }
        Row_ {
          visible: root.asleepCount > 0
          label: "Asleep"
          value: root.asleepCount
          url: root.links.homepage
        }
        Row_ {
          visible: root.downServices.length > 0
          label: "Down"
          value: root.downServices.map(function(s) { return s.name }).join(", ")
          alert: true
          url: root.links.homepage
        }

        ServiceGroup { title: "Infra"; group: "infra" }
        ServiceGroup { title: "Internal"; group: "internal" }
        ServiceGroup { title: "External"; group: "external" }
      }
    }
  }
}

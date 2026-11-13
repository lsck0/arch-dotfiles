pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "homelab"
  barPriority: 30
  hoverPanel: true
  hoverFill: true
  panelPinOnClick: false

  property bool received: false
  property bool ok: false
  property string error: ""
  property bool absent: false
  // the last good homelab-status.nu answer
  property var lab: ({
    links: { homepage: "", dashboard: "", alerts: "", proxmox: "", nas: "" },
    services: [], alerts: [], host: {}, storage: {}, traffic: {}, clients: {}
  })

  readonly property var monitored: lab.services.filter(function(s) { return s.up === true || s.up === false })
  readonly property var downServices: monitored.filter(function(s) { return !s.up && !s.onDemand })
  readonly property int upCount: monitored.filter(function(s) { return s.up }).length
  readonly property int asleepCount: monitored.filter(function(s) { return !s.up && s.onDemand }).length
  readonly property int problemCount: lab.alerts.length + downServices.length
  readonly property real memFraction: (Number(lab.host.memTotalGb) || 0) > 0
    ? (Number(lab.host.memUsedGb) || 0) / Number(lab.host.memTotalGb) : 0
  readonly property bool backupStale: lab.storage.backupAgeMin === null || lab.storage.backupAgeMin === undefined
    || lab.storage.backupAgeMin > 26 * 60

  function open(url) {
    if (!url) return
    Quickshell.execDetached(["uwsm-app", "--", "xdg-open", url])
    if (root.bar) root.bar.closePanel(root.moduleName)
  }

  function num(value, suffix) {
    return value === null || value === undefined ? "--" : value + (suffix || "")
  }

  visible: !root.absent
  implicitWidth: root.absent ? 0 : trigger.implicitWidth + Style.bar.itemPaddingX * 2
  implicitHeight: Style.bar.sizeHorizontal

  JsonProcess {
    id: statusProc
    running: true
    streaming: true
    command: [Paths.barWidget("homelab-status.nu"), panel.visible ? "30" : "300"]
    onParsed: function(s) {
      root.received = true
      root.ok = s.ok === true
      root.error = s.error || ""
      // hide on a missing checkout, but keep polling: homelab-status.nu re-stats lab.json each loop, so the widget
      // returns once it reappears
      root.absent = root.error === "source"
      if (!root.ok) return
      root.lab = s
    }
  }

  Connections {
    target: panel
    function onVisibleChanged() {
      if (root.absent) return
      statusProc.running = false
      statusProc.running = true
      if (panel.visible) vpnProc.run()
    }
  }

  // toggle-vpn.nu's record: "Connect homelab VPN" only where the vpn exists and is down, read while the panel shows
  property var vpn: ({ available: false, state: "off" })
  readonly property bool vpnUp: vpn.available === true && vpn.state === "on"
  readonly property bool vpnOffered: vpn.available === true && vpn.state === "off"
  JsonProcess {
    id: vpnProc
    command: [Paths.toggle("toggle-vpn.nu"), "get", "--json"]
    onParsed: function(data) { if (data) root.vpn = data }
  }

  Connections {
    target: ToggleEvents
    function onChanged(script) { if (script === "toggle-vpn.nu" && panel.visible) vpnProc.run() }
  }

  Row {
    id: trigger
    anchors.centerIn: parent
    spacing: Style.spacing.xs

    Label {
      anchors.verticalCenter: parent.verticalCenter
      text: root.ok || !root.received ? "\u{f048d}" : "\u{f048e}"
      color: root.ok && root.problemCount > 0 ? Colors.urgent : Colors.textDim
      icon: true
      font.pixelSize: Style.font.icon
      layer.enabled: Style.fx.glow > 0 && root.ok && root.problemCount > 0
      layer.effect: Glow { shadowColor: Colors.urgent }
    }
    Label {
      anchors.verticalCenter: parent.verticalCenter
      visible: root.ok && root.problemCount > 0
      text: root.problemCount
      color: Colors.urgentText
      layer.enabled: Style.fx.glow > 0
      layer.effect: Glow { shadowColor: Colors.urgent }
    }
  }

  MouseArea {
    anchors.fill: parent
    cursorShape: Qt.PointingHandCursor
    onClicked: root.open(root.lab.links.homepage)
  }

  component LinkStat: StatRow {
    property string url: ""
    property bool alert: false
    valueColor: alert ? Colors.urgentText : Colors.menu.text
    clickable: url !== ""
    onActivated: root.open(url)
  }

  component ClientList: Column {
    id: list
    property string title: ""
    property var rows: []

    Label {
      text: list.title
      color: Colors.accentText
      caption: true
      font.capitalization: Font.AllUppercase
      font.letterSpacing: Style.headerTracking
      elide: Text.ElideRight
      width: list.width
      bottomPadding: Style.spacing.xxs
    }

    Repeater {
      model: list.rows
      delegate: Item {
        id: entry
        required property var modelData
        width: list.width
        implicitHeight: entryName.implicitHeight + Style.spacing.xxs

        Rectangle {
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          height: parent.height
          width: parent.width * Math.max(0, Math.min(100, entry.modelData.pct || 0)) / 100
          radius: Style.shape.data
          color: Util.alpha(Colors.accent, Style.tintFillAlpha)
        }
        Label {
          id: entryName
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          width: parent.width - entryCount.implicitWidth - Style.spacing.xs
          text: entry.modelData.name
          elide: Text.ElideRight
          color: Colors.menu.text
          caption: true
        }
        Label {
          id: entryCount
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          text: entry.modelData.count
          color: Colors.menu.text
          caption: true
        }
      }
    }
  }

  component ServiceGroup: Column {
    id: groupBox
    property string title: ""
    property string group: ""
    readonly property var members: root.lab.services.filter(function(s) { return s.group === groupBox.group })
    width: parent.width
    visible: members.length > 0
    spacing: Style.spacing.xs

    Label {
      text: groupBox.title
      color: Colors.accentText
      caption: true
    }

    Grid {
      id: serviceGrid
      width: parent.width
      columns: 3
      columnSpacing: Style.spacing.sm

      Repeater {
        model: groupBox.members
        delegate: Item {
          id: tile
          required property var modelData
          readonly property bool asleep: modelData.up === false && modelData.onDemand
          readonly property bool down: modelData.up === false && !modelData.onDemand
          activeFocusOnTab: !!modelData.url
          Keys.onReturnPressed: root.open(tile.modelData.url)
          Keys.onEnterPressed: root.open(tile.modelData.url)
          Keys.onSpacePressed: root.open(tile.modelData.url)
          width: (serviceGrid.width - serviceGrid.columnSpacing * (serviceGrid.columns - 1)) / serviceGrid.columns
          height: tileName.implicitHeight + Style.spacing.xs * 2

          Rectangle {
            anchors.fill: parent
            anchors.leftMargin: -Style.spacing.xs
            radius: Style.shape.data
            color: tile.activeFocus ? Style.focusFillFor(Colors.foreground, Colors.accent)
              : tileMouse.containsMouse && tile.modelData.url ? Style.hoverFill : "transparent"
            Behavior on color { ColorAnimation { duration: Style.motion.fast; easing.type: Style.motion.fastEasing } }
          }
          Row {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.spacing.xs

            Label {
              anchors.verticalCenter: parent.verticalCenter
              text: tile.asleep ? "o" : "*"
              color: tile.down ? Colors.urgentText : tile.asleep ? Colors.textDim : Colors.menu.text
            }
            Label {
              id: tileName
              anchors.verticalCenter: parent.verticalCenter
              width: tile.width - Style.spacing.xs - Style.font.body
              text: tile.modelData.name
              elide: Text.ElideRight
              color: tile.down ? Colors.urgentText : tile.asleep ? Colors.textDim : Colors.menu.text
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

  component GaugeRow: MetricRow {
    property bool alert: false
    property string url: ""
    valueBeside: true
    tint: alert ? Colors.urgent : Colors.accent
    clickable: url !== ""
    onActivated: root.open(url)
  }

  HoverPanel {
    id: panel
    anchorWidget: root
    title: "Homelab"
    implicitWidth: Style.panelWidth.wide

    Column {
      width: parent.width
      spacing: Style.spacing.sm

      LinkStat {
        visible: !root.ok
        label: "Status"
        value: !root.received ? "Connecting..." : root.error === "source" ? "No homelab checkout"
          : root.vpnUp ? "VPN up, lab unreachable" : "Unreachable"
        alert: root.received
      }
      PanelSeparator { visible: vpnRow.visible }
      PanelSectionHeader { text: "Tools"; visible: vpnRow.visible }
      PanelRow {
        id: vpnRow
        width: parent.width
        visible: root.received && !root.ok && root.error !== "source" && root.vpnOffered
        glyph: "\u{f0582}"   // md-vpn
        label: "Connect homelab VPN"
        onActivated: {
          Quickshell.execDetached([Paths.toggle("toggle-vpn.nu"), "on"])
          if (root.bar) root.bar.closePanel(root.moduleName)
        }
      }

      Column {
        width: parent.width
        visible: root.ok
        spacing: Style.spacing.sm

        Column {
          width: parent.width
          visible: root.lab.alerts.length > 0
          spacing: Style.spacing.sm

          PanelSectionHeader { text: "Alerts"; foreground: Colors.urgent }
          Repeater {
            model: root.lab.alerts
            delegate: LinkStat {
              required property var modelData
              label: modelData.target || modelData.name
              value: modelData.target ? modelData.name : ""
              note: Util.ago(modelData.minutes)
              url: root.lab.links.alerts
              alert: true
            }
          }
          PanelSeparator {}
        }

        PanelSectionHeader { text: "Host" }
        Item {
          width: parent.width
          implicitHeight: Math.max(hostHero.implicitHeight, hostReads.implicitHeight)
          height: implicitHeight
          Hero { id: hostHero; anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; value: String(Math.round(Number(root.lab.host.cpuPct) || 0)); unit: "%" }
          Column {
            id: hostReads
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width * 0.6
            spacing: Style.spacing.xxs
            LinkStat {
              label: "Memory"
              value: root.num(root.lab.host.memUsedGb) + " / " + root.num(root.lab.host.memTotalGb, " GB")
              url: root.lab.links.proxmox
            }
            LinkStat { label: "Temperature"; value: root.num(root.lab.host.tempC, "\u00b0C"); url: root.lab.links.proxmox }
            LinkStat { label: "Uptime"; value: root.num(root.lab.host.uptimeH, " h"); url: root.lab.links.proxmox }
          }
        }
        // one line and a gauge each: the hero and the readings above already carry the numbers
        GaugeRow { label: "CPU"; value: root.num(root.lab.host.cpuPct, "%"); fraction: (Number(root.lab.host.cpuPct) || 0) / 100 }
        GaugeRow { label: "Memory"; value: Math.round(root.memFraction * 100) + "%"; fraction: root.memFraction }

        PanelSeparator {}
        PanelSectionHeader { text: "Storage" }
        GaugeRow {
          label: "NAS free"
          value: root.num(root.lab.storage.nasFreeGb) + " / " + root.num(root.lab.storage.nasTotalGb, " GB")
          fraction: (Number(root.lab.storage.nasTotalGb) || 0) > 0 ? (Number(root.lab.storage.nasFreeGb) || 0) / Number(root.lab.storage.nasTotalGb) : 0
          url: root.lab.links.nas
        }
        GaugeRow {
          label: "Disks OK"
          value: root.num(root.lab.storage.disksHealthy) + " / " + root.num(root.lab.storage.disksTotal)
          fraction: (Number(root.lab.storage.disksTotal) || 0) > 0 ? (Number(root.lab.storage.disksHealthy) || 0) / Number(root.lab.storage.disksTotal) : 0
          alert: root.lab.storage.disksHealthy < root.lab.storage.disksTotal
          url: root.lab.links.dashboard
        }
        GaugeRow {
          visible: root.lab.storage.nvmeWearPct !== null && root.lab.storage.nvmeWearPct !== undefined
          label: "NVMe wear"
          value: root.num(root.lab.storage.nvmeWearPct, "%")
          fraction: (Number(root.lab.storage.nvmeWearPct) || 0) / 100
          url: root.lab.links.dashboard
        }
        LinkStat {
          label: "Last backup"
          value: root.lab.storage.backupAgeMin === null || root.lab.storage.backupAgeMin === undefined
            ? "never" : Util.ago(root.lab.storage.backupAgeMin)
          alert: root.backupStale
          url: root.lab.links.nas
        }

        PanelSeparator {}
        PanelSectionHeader { text: "Traffic" }
        LinkStat { label: "Internal"; value: root.num(root.lab.traffic.internalRps, " req/s"); url: root.lab.links.dashboard }
        LinkStat { label: "Public"; value: root.num(root.lab.traffic.externalRps, " req/s"); url: root.lab.links.dashboard }
        LinkStat {
          label: "Server errors"
          value: root.num(root.lab.traffic.errorRps, " req/s")
          alert: root.lab.traffic.errorRps > 0
          url: root.lab.links.dashboard
        }

        Column {
          width: parent.width
          visible: (root.lab.clients.countries || []).length > 0
          spacing: Style.spacing.sm

          PanelSeparator {}
          Row {
            width: parent.width
            spacing: Style.spacing.xs
            PanelSectionHeader { text: "Incoming" }
            Label {
              anchors.verticalCenter: parent.verticalCenter
              text: root.lab.clients.window || ""
              dim: true
              caption: true
            }
          }

          Grid {
            id: clientGrid
            width: parent.width
            columns: 4
            columnSpacing: Style.spacing.sm
            readonly property real cellWidth:
              (width - columnSpacing * (columns - 1)) / columns

            ClientList { width: clientGrid.cellWidth; title: "From"; rows: root.lab.clients.countries || [] }
            ClientList { width: clientGrid.cellWidth; title: "Clients"; rows: root.lab.clients.agents || [] }
            ClientList { width: clientGrid.cellWidth; title: "Asking for"; rows: root.lab.clients.hosts || [] }
            ClientList { width: clientGrid.cellWidth; title: "How it went"; rows: root.lab.clients.traffic || [] }
          }
        }

        PanelSeparator {}
        PanelSectionHeader { text: "Services" }
        LinkStat {
          label: "Up"
          value: root.upCount + " / " + root.monitored.length
          note: root.asleepCount > 0 ? root.asleepCount + " asleep" : ""
          url: root.lab.links.homepage
        }
        LinkStat {
          visible: root.downServices.length > 0
          label: "Down"
          value: root.downServices.map(function(s) { return s.name }).join(", ")
          alert: true
          url: root.lab.links.homepage
        }

        ServiceGroup { title: "Infra"; group: "infra" }
        ServiceGroup { title: "Internal"; group: "internal" }
        ServiceGroup { title: "External"; group: "external" }
      }
    }
  }
}

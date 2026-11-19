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
  // when the last good answer came: an unreachable lab keeps showing it under its age
  property real updatedMs: 0
  // the last good homelab-status.nu answer
  property var lab: ({
    links: { homepage: "", dashboard: "", alerts: "", proxmox: "", nas: "" },
    services: [], alerts: [], minecraft: [], host: {}, storage: {}, traffic: {}, clients: {}
  })

  readonly property var monitored: lab.services.filter(function(s) { return s.up === true || s.up === false })
  readonly property var downServices: monitored.filter(function(s) { return !s.up && !s.onDemand })
  readonly property int upCount: monitored.filter(function(s) { return s.up }).length
  readonly property int asleepCount: monitored.filter(function(s) { return !s.up && s.onDemand }).length
  readonly property var mcServers: lab.minecraft || []
  readonly property int mcFailingCount: mcServers.filter(function(s) { return s.startFailures > 0 }).length
  readonly property int mcPlayers: mcServers.reduce(function(sum, s) { return s.phase === "running" ? sum + s.players : sum }, 0)
  readonly property real tpsUrgentBelow: 15
  readonly property real tpsWarnBelow: 19.5
  readonly property int problemCount: lab.alerts.length + downServices.length + mcFailingCount
  readonly property real memFraction: (Number(lab.host.memTotalGb) || 0) > 0
    ? (Number(lab.host.memUsedGb) || 0) / Number(lab.host.memTotalGb) : 0
  // alerts and client lists past this many rows wait behind an expand row
  readonly property int rowsShownMax: 3
  property bool alertsShowAll: false
  property bool clientsShowAll: false
  readonly property var alertsShown: alertsShowAll ? lab.alerts : lab.alerts.slice(0, rowsShownMax)
  readonly property int clientRowsMax: Math.max((lab.clients.countries || []).length, (lab.clients.agents || []).length,
    (lab.clients.hosts || []).length, (lab.clients.traffic || []).length)
  readonly property bool backupStale: lab.storage.backupAgeMin === null || lab.storage.backupAgeMin === undefined
    || lab.storage.backupAgeMin > 26 * 60

  function open(url) {
    if (!url) return
    Quickshell.execDetached(["uwsm-app", "--", "xdg-open", url])
    root.closePanel()
  }

  function num(value, suffix) {
    return value === null || value === undefined ? "--" : value + (suffix || "")
  }

  function sizeOf(usedGib, totalGib) {
    return (Number(totalGib) || 0) > 0 ? Util.bytesOf((Number(usedGib) || 0) * Util.bytesPerGib, totalGib * Util.bytesPerGib) : "--"
  }

  visible: !root.absent
  implicitWidth: root.absent ? 0 : trigger.implicitWidth + Style.bar.itemPaddingX * 2
  implicitHeight: Style.bar.sizeHorizontal

  // the closed panel only feeds the bar's problem count; away (no home link, no wg0) the helper answers without the
  // network, so a short poll brings the widget back soon after a home link or the vpn comes up
  readonly property bool away: root.error === "away"
  // away, the vpn's state decides whether the widget shows, so it is read then and not only with the panel open
  onAwayChanged: if (away) vpnProc.run()
  readonly property int awayIntervalS: 30
  readonly property int hiddenIntervalS: away ? awayIntervalS : Power.onBattery ? 900 : 300
  readonly property int statusRestartDelayMs: 5 * 1000

  function restartStatus() {
    statusProc.running = false
    statusProc.running = true
  }

  onHiddenIntervalSChanged: if (root.error !== "source" && !panel.visible) restartStatus()

  JsonProcess {
    id: statusProc
    running: true
    streaming: true
    command: [Paths.barWidget("homelab-status.nu")].concat(panel.visible ? ["30", "--clients"] : [String(root.hiddenIntervalS)])
    // the helper loops forever: an exit is a crash, restarted after a pause so a crash loop stays cheap
    onRunningChanged: if (!running) statusRestart.restart()
    onParsed: function(s) {
      root.received = true
      root.ok = s.ok === true
      root.error = s.error || ""
      // hide on a missing checkout, and away unless the vpn is there to connect (the panel offers it); keep polling:
      // the widget returns once lab.json reappears or a home link or wg0 comes up
      root.absent = root.error === "source" || (root.away && !root.vpnOffered)
      if (!root.ok) return
      // the closed panel's poll carries no clients: the last ones stay for the next open
      if (s.clients === undefined) s.clients = root.lab.clients
      root.lab = s
      root.updatedMs = Date.now()
    }
  }

  Timer {
    id: statusRestart
    interval: root.statusRestartDelayMs
    onTriggered: if (!statusProc.running) statusProc.running = true
  }

  Connections {
    target: panel
    function onVisibleChanged() {
      root.alertsShowAll = false
      root.clientsShowAll = false
      if (root.absent) return
      root.restartStatus()
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
    onParsed: function(data) {
      if (data) root.vpn = data
      if (root.error !== "source") root.absent = root.away && !root.vpnOffered
    }
  }

  Connections {
    target: ToggleEvents
    function onChanged(script) {
      if (script !== "toggle-vpn.nu") return
      // wg0 came or went: the closed panel's next poll may be minutes off
      if (root.error !== "source") root.restartStatus()
      if (panel.visible || root.away) vpnProc.run()
    }
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
    Label {
      anchors.verticalCenter: parent.verticalCenter
      visible: root.ok && root.mcPlayers > 0
      text: "\u{f0373}"   // md-minecraft
      color: Colors.textDim
      icon: true
      font.pixelSize: Style.font.icon
    }
    Label {
      anchors.verticalCenter: parent.verticalCenter
      visible: root.ok && root.mcPlayers > 0
      text: root.mcPlayers
      color: Colors.bar.text
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
      model: root.clientsShowAll ? list.rows : list.rows.slice(0, root.rowsShownMax)
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
      font.capitalization: Font.AllUppercase
      font.letterSpacing: Style.headerTracking
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
            color: tile.activeFocus ? Style.focusFill
              : tileMouse.containsMouse && tile.modelData.url ? Style.hoverFill : "transparent"
            Behavior on color { ColorAnimation { duration: Style.motion.fast; easing.type: Style.motion.fastEasing } }
          }
          Row {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.spacing.xs

            Label {
              anchors.verticalCenter: parent.verticalCenter
              // up, asleep and down differ by mark, not only by colour
              text: tile.down ? "x" : tile.asleep ? "o" : "*"
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
        value: !root.received ? "Connecting" : root.error === "source" ? "No homelab checkout"
          : root.vpnUp ? "VPN up, lab unreachable" : "Unreachable"
        alert: root.received
      }
      LinkStat {
        visible: !root.ok && root.updatedMs > 0
        label: "Last answer"
        value: Qt.formatDateTime(new Date(root.updatedMs), Util.dayFormat + " " + Util.timeFormat)
      }
      PanelSeparator { visible: vpnRow.visible }
      PanelRow {
        id: vpnRow
        width: parent.width
        visible: root.received && !root.ok && root.error !== "source" && root.vpnOffered
        glyph: "\u{f0582}"   // md-vpn
        label: "Connect homelab VPN"
        onActivated: {
          Quickshell.execDetached([Paths.toggle("toggle-vpn.nu"), "on"])
          root.closePanel()
        }
      }

      PanelSeparator { visible: !root.ok && root.updatedMs > 0 }

      Column {
        width: parent.width
        visible: root.updatedMs > 0
        spacing: Style.spacing.sm

        Column {
          width: parent.width
          visible: root.lab.alerts.length > 0
          spacing: Style.spacing.sm

          PanelSectionHeader { text: "Alerts"; foreground: Colors.urgent }
          Repeater {
            model: root.alertsShown
            delegate: LinkStat {
              required property var modelData
              label: modelData.target || modelData.name
              value: modelData.target ? modelData.name : ""
              note: Util.ago(modelData.minutes)
              url: root.lab.links.alerts
              alert: true
            }
          }
          PanelRow {
            visible: root.alertsShown.length < root.lab.alerts.length
            width: parent.width
            label: "All alerts"
            trailing: "+" + (root.lab.alerts.length - root.alertsShown.length)
            onActivated: root.alertsShowAll = true
          }
          PanelSeparator {}
        }

        PanelSectionHeader { text: root.lab.host.uptimeH === null || root.lab.host.uptimeH === undefined ? "Host" : "Host :: up " + root.lab.host.uptimeH + " h" }
        GaugeRow {
          label: "CPU"
          value: root.num(root.lab.host.cpuPct, "%")
          note: root.num(root.lab.host.tempC, "\u00b0C")
          fraction: (Number(root.lab.host.cpuPct) || 0) / 100
          url: root.lab.links.proxmox
        }
        GaugeRow {
          label: "Memory"
          value: Math.round(root.memFraction * 100) + "%"
          note: root.sizeOf(root.lab.host.memUsedGb, root.lab.host.memTotalGb)
          fraction: root.memFraction
          url: root.lab.links.proxmox
        }

        PanelSeparator {}
        PanelSectionHeader { text: "Storage" }
        GaugeRow {
          label: "NAS free"
          value: root.sizeOf(root.lab.storage.nasFreeGb, root.lab.storage.nasTotalGb)
          fraction: (Number(root.lab.storage.nasTotalGb) || 0) > 0 ? (Number(root.lab.storage.nasFreeGb) || 0) / Number(root.lab.storage.nasTotalGb) : 0
          url: root.lab.links.nas
        }
        GaugeRow {
          label: "Disks OK"
          value: root.num(root.lab.storage.disksHealthy) + " / " + root.num(root.lab.storage.disksTotal)
          fraction: (Number(root.lab.storage.disksTotal) || 0) > 0 ? (Number(root.lab.storage.disksHealthy) || 0) / Number(root.lab.storage.disksTotal) : 0
          note: root.lab.storage.nvmeWearPct === null || root.lab.storage.nvmeWearPct === undefined
            ? "" : "NVMe wear " + root.lab.storage.nvmeWearPct + "%"
          alert: root.lab.storage.disksHealthy < root.lab.storage.disksTotal
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
        LinkStat {
          label: "Internal / public"
          value: root.num(root.lab.traffic.internalRps) + " / " + root.num(root.lab.traffic.externalRps, " req/s")
          url: root.lab.links.dashboard
        }
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

          Grid {
            id: clientGrid
            width: parent.width
            columns: 4
            columnSpacing: Style.spacing.sm
            readonly property real cellWidth:
              (width - columnSpacing * (columns - 1)) / columns

            ClientList { width: clientGrid.cellWidth; title: root.lab.clients.window ? "From :: " + root.lab.clients.window : "From"; rows: root.lab.clients.countries || [] }
            ClientList { width: clientGrid.cellWidth; title: "Clients"; rows: root.lab.clients.agents || [] }
            ClientList { width: clientGrid.cellWidth; title: "Asking for"; rows: root.lab.clients.hosts || [] }
            ClientList { width: clientGrid.cellWidth; title: "How it went"; rows: root.lab.clients.traffic || [] }
          }
          PanelRow {
            visible: !root.clientsShowAll && root.clientRowsMax > root.rowsShownMax
            width: parent.width
            label: "All clients"
            trailing: "+" + (root.clientRowsMax - root.rowsShownMax)
            onActivated: root.clientsShowAll = true
          }
        }

        Column {
          width: parent.width
          visible: root.mcServers.length > 0
          spacing: Style.spacing.sm

          PanelSeparator {}
          PanelSectionHeader { text: "Minecraft" }
          Repeater {
            model: root.mcServers
            delegate: Item {
              id: server
              required property var modelData
              readonly property bool running: modelData.phase === "running"
              readonly property bool asleep: modelData.phase === "sleeping"
              readonly property bool failing: modelData.startFailures > 0
              readonly property bool measured: modelData.tps !== null && modelData.tps !== undefined
              width: parent ? parent.width : 0
              implicitHeight: serverName.implicitHeight + Style.spacing.xxs * 2

              Label {
                id: serverName
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                width: Math.min(implicitWidth, parent.width - readings.implicitWidth - Style.spacing.md)
                text: server.modelData.name
                color: server.asleep && !server.failing ? Colors.textDim : Colors.menu.text
                elide: Text.ElideRight
                caption: true
                font.capitalization: Font.AllUppercase
                font.letterSpacing: Style.labelTracking
              }
              Row {
                id: readings
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.spacing.sm

                Label {
                  visible: server.failing
                  text: "start failed"
                  color: Colors.urgentText
                  caption: true
                }
                Label {
                  text: server.modelData.phase
                  color: server.running ? Colors.menu.text : Colors.textDim
                  caption: true
                }
                Label {
                  visible: server.running || server.modelData.players > 0
                  text: server.modelData.players + (server.modelData.players === 1 ? " player" : " players")
                  color: Colors.menu.text
                  caption: true
                  font.features: { "tnum": 1 }
                }
                Label {
                  visible: server.measured
                  text: server.measured ? server.modelData.tps.toFixed(1) + " tps" : ""
                  color: !server.measured ? Colors.menu.text
                    : server.modelData.tps < root.tpsUrgentBelow ? Colors.urgentText
                    : server.modelData.tps < root.tpsWarnBelow ? Colors.warnText : Colors.menu.text
                  caption: true
                  font.features: { "tnum": 1 }
                }
                Label {
                  visible: (Number(server.modelData.memLimitBytes) || 0) > 0
                  text: visible ? Util.bytesOf(server.modelData.memUsedBytes, server.modelData.memLimitBytes) : ""
                  dim: true
                  caption: true
                  font.features: { "tnum": 1 }
                }
              }
            }
          }
        }

        PanelSeparator {}
        PanelSectionHeader {
          text: "Services :: " + root.upCount + " / " + root.monitored.length + " up"
            + (root.asleepCount > 0 ? ", " + root.asleepCount + " asleep" : "")
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
        ServiceGroup { title: "Apps"; group: "apps" }
      }
    }
  }
}

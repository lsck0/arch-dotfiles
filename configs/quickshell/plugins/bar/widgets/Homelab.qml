import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "homelab"

  property bool received: false
  property bool ok: false
  // "source" means no readable homelab checkout
  property string error: ""
  // no checkout (guest, or not cloned): hidden and no longer polled
  property bool absent: false
  property var links: ({ homepage: "", dashboard: "", alerts: "", proxmox: "", nas: "" })
  property var services: []
  property var alerts: []
  property var host: ({})
  property var storage: ({})
  property var traffic: ({})
  property var clients: ({})

  property var cpuHist: []
  property var memHist: []

  // link-only entries have up === null
  readonly property var monitored: services.filter(function(s) { return s.up === true || s.up === false })
  readonly property var downServices: monitored.filter(function(s) { return !s.up && !s.onDemand })
  readonly property int upCount: monitored.filter(function(s) { return s.up }).length
  readonly property int asleepCount: monitored.filter(function(s) { return !s.up && s.onDemand }).length
  readonly property int problemCount: alerts.length + downServices.length
  readonly property real memFraction: (Number(host.memTotalGb) || 0) > 0
    ? (Number(host.memUsedGb) || 0) / Number(host.memTotalGb) : 0
  // nightly backups, 26h leaves some slack
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
    return value === null || value === undefined ? "--" : value + (suffix || "")
  }

  visible: !root.absent
  implicitWidth: root.absent ? 0 : trigger.implicitWidth + Style.bar.itemPaddingX * 2
  implicitHeight: barSize

  Process {
    id: statusProc
    running: true
    // full detail only while the panel is open
    command: panel.visible
      ? [Paths.barWidget("homelab-status.py"), "30"]
      : [Paths.barWidget("homelab-status.py"), "300", "--summary"]
    stdout: SplitParser {
      splitMarker: "\n"
      onRead: function(line) {
        if (!line) return
        try {
          var s = JSON.parse(line)
          root.received = true
          root.ok = s.ok === true
          root.error = s.error || ""
          if (!root.ok) {
            if (root.error === "source") { root.absent = true; statusProc.running = false }
            return
          }
          if (s.links) root.links = s.links
          root.services = s.services || []
          root.alerts = s.alerts || []
          // summary lines carry no host detail, keep the last full sample
          if (!s.host) return
          root.host = s.host
          root.storage = s.storage || {}
          root.traffic = s.traffic || {}
          root.clients = s.clients || {}
          root.cpuHist = Util.historyPush(root.cpuHist, Number(root.host.cpuPct) || 0)
          root.memHist = Util.historyPush(root.memHist, root.memFraction * 100)
        } catch (e) {}
      }
    }
  }

  // restart so the new cadence applies at once
  Connections {
    target: panel
    function onVisibleChanged() {
      if (root.absent) return
      statusProc.running = false
      statusProc.running = true
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
      layer.enabled: Style.fx.glow > 0 && root.ok && root.problemCount > 0
      layer.effect: Glow { shadowColor: Color.urgent }
    }
    Text {
      anchors.verticalCenter: parent.verticalCenter
      visible: root.ok && root.problemCount > 0
      textFormat: Text.PlainText
      text: root.problemCount
      color: Color.urgent
      font.family: root.bar ? root.bar.fontFamily : Style.font.family
      font.pixelSize: Style.font.body
      layer.enabled: Style.fx.glow > 0
      layer.effect: Glow { shadowColor: Color.urgent }
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

  // hover fill bleeds past the edge so text stays aligned with headers
  component StatRow: Item {
    id: kv
    property string label: ""
    property string value: ""
    property string url: ""
    property bool alert: false
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

  component ClientList: Column {
    id: list
    property string title: ""
    property var rows: []
    spacing: 0

    Text {
      text: list.title
      color: Color.accent
      textFormat: Text.PlainText
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
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
          // behind the text, the column has no width for a track
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          height: parent.height
          width: parent.width * Math.max(0, Math.min(100, entry.modelData.pct || 0)) / 100
          radius: Style.cornerRadius
          color: Util.alpha(Color.accent, 0.15)
        }
        Text {
          id: entryName
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          width: parent.width - entryCount.implicitWidth - Style.spacing.sm
          textFormat: Text.PlainText
          text: entry.modelData.name
          elide: Text.ElideRight
          color: Color.menu.text
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
        }
        Text {
          id: entryCount
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: entry.modelData.count
          color: Color.menu.text
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
        }
      }
    }
  }

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

            // * up or link-only, o asleep
            Text {
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: tile.asleep ? "o" : "*"
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

  component Hero: Row {
    property int pct: 0
    property color tint: Color.accent
    spacing: Style.spacing.xxs
    Text {
      id: heroNum
      anchors.bottom: parent.bottom
      text: parent.pct
      color: parent.tint
      font.family: Style.font.family
      font.pixelSize: Math.round(Style.font.display * 1.7)
      font.bold: true
      font.letterSpacing: Style.displayTracking
      layer.enabled: Style.fx.glow > 0
      layer.effect: Glow { shadowColor: parent.tint }
    }
    Text {
      anchors.bottom: heroNum.bottom
      anchors.bottomMargin: Math.round(Style.font.display * 0.35)
      text: "%"
      color: parent.tint
      opacity: Style.emphasis.dim
      font.family: Style.font.family
      font.pixelSize: Style.font.title
    }
  }

  component MetricHeader: Row {
    id: mh
    property string label: ""
    property string readout: ""
    property color tint: Color.accent
    Text {
      width: mh.width * 0.5
      text: mh.label
      color: mh.tint
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      font.bold: true
      font.capitalization: Font.AllUppercase
      font.letterSpacing: Style.headerTracking
    }
    Text {
      width: mh.width * 0.5
      horizontalAlignment: Text.AlignRight
      text: mh.readout
      color: mh.tint
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      font.letterSpacing: Style.displayTracking
    }
  }

  component MetricGraph: Column {
    id: mg
    property var history: []
    property real fraction: 0
    property color tint: Color.accent
    property string label: ""
    property string readout: ""
    property int maxValue: 100
    width: parent ? parent.width : 0
    spacing: Style.spacing.xs
    MetricHeader { width: mg.width; visible: mg.label !== ""; label: mg.label; readout: mg.readout; tint: mg.tint }
    Sparkline { width: mg.width; height: Style.space(34); values: mg.history; minValue: 0; maxValue: mg.maxValue; color: mg.tint }
    BarGauge { width: mg.width; height: Style.spacing.md; segments: 24; value: mg.fraction; color: mg.tint }
  }

  component GaugeRow: Column {
    id: gr
    property string label: ""
    property string readout: ""
    property real fraction: 0
    property color tint: Color.accent
    width: parent ? parent.width : 0
    spacing: Style.spacing.xxs
    MetricHeader { width: gr.width; label: gr.label; readout: gr.readout; tint: gr.tint }
    BarGauge { width: gr.width; height: Style.spacing.md; segments: 24; value: gr.fraction; color: gr.tint }
  }

  HoverPanel {
    id: panel
    bar: root.bar
    moduleName: root.moduleName
    anchorWidget: root
    title: "Homelab"
    implicitWidth: Style.panelWidth.wide
    implicitHeight: Math.min(Style.space(880), content.implicitHeight + padding * 2 + titleInset)

    Flickable {
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
        spacing: Style.spacing.md

        StatRow {
          visible: !root.ok
          label: "Status"
          value: !root.received ? "Connecting..." : root.error === "source" ? "No homelab checkout" : "Unreachable"
          alert: root.received
        }
        PanelSeparator { visible: root.received && !root.ok && root.error !== "source" }
        PanelSectionHeader { text: "Tools"; visible: root.received && !root.ok && root.error !== "source" }
        // off the lan the monitor vm is only reachable over wireguard
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

          Column {
            width: parent.width
            visible: root.alerts.length > 0
            spacing: Style.spacing.md

            PanelSectionHeader { text: "Alerts"; foreground: Color.urgent }
            Repeater {
              model: root.alerts
              delegate: StatRow {
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

          PanelSectionHeader { text: "Host" }
          Item {
            width: parent.width
            implicitHeight: Math.max(hostHero.implicitHeight, hostReads.implicitHeight)
            height: implicitHeight
            Hero { id: hostHero; anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; pct: Number(root.host.cpuPct) || 0 }
            Column {
              id: hostReads
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              width: parent.width * 0.6
              spacing: Style.spacing.xxs
              StatRow {
                label: "Memory"
                value: root.num(root.host.memUsedGb) + " / " + root.num(root.host.memTotalGb, " GB")
                url: root.links.proxmox
              }
              StatRow { label: "Temperature"; value: root.num(root.host.tempC, "°C"); url: root.links.proxmox }
              StatRow { label: "Uptime"; value: root.num(root.host.uptimeH, " h"); url: root.links.proxmox }
            }
          }
          MetricGraph { label: "Usage"; readout: root.num(root.host.cpuPct, "%"); history: root.cpuHist; fraction: (Number(root.host.cpuPct) || 0) / 100 }
          MetricGraph {
            label: "Memory"
            readout: Math.round(root.memFraction * 100) + "%"
            history: root.memHist
            fraction: root.memFraction
          }

          PanelSeparator {}
          PanelSectionHeader { text: "Storage" }
          StatRow {
            label: "NAS free"
            value: root.num(root.storage.nasFreeGb) + " / " + root.num(root.storage.nasTotalGb, " GB")
            url: root.links.nas
          }
          StatRow {
            label: "Disks"
            value: root.num(root.storage.disksHealthy) + " / " + root.num(root.storage.disksTotal, " healthy")
            alert: root.storage.disksHealthy < root.storage.disksTotal
            url: root.links.dashboard
          }
          StatRow { label: "NVMe wear"; value: root.num(root.storage.nvmeWearPct, "%"); url: root.links.dashboard }
          StatRow {
            label: "Last backup"
            value: root.storage.backupAgeMin === null || root.storage.backupAgeMin === undefined
              ? "never" : root.ago(root.storage.backupAgeMin)
            alert: root.backupStale
            url: root.links.nas
          }
          GaugeRow {
            label: "NAS free"
            readout: root.num(root.storage.nasFreeGb, " GB")
            fraction: (Number(root.storage.nasTotalGb) || 0) > 0 ? (Number(root.storage.nasFreeGb) || 0) / Number(root.storage.nasTotalGb) : 0
          }
          GaugeRow {
            label: "Disks OK"
            readout: root.num(root.storage.disksHealthy) + " / " + root.num(root.storage.disksTotal)
            fraction: (Number(root.storage.disksTotal) || 0) > 0 ? (Number(root.storage.disksHealthy) || 0) / Number(root.storage.disksTotal) : 0
            tint: root.storage.disksHealthy < root.storage.disksTotal ? Color.urgent : Color.accent
          }
          GaugeRow {
            visible: root.storage.nvmeWearPct !== null && root.storage.nvmeWearPct !== undefined
            label: "NVMe wear"
            readout: root.num(root.storage.nvmeWearPct, "%")
            fraction: (Number(root.storage.nvmeWearPct) || 0) / 100
          }

          PanelSeparator {}
          PanelSectionHeader { text: "Traffic" }
          StatRow { label: "Internal"; value: root.num(root.traffic.internalRps, " req/s"); url: root.links.dashboard }
          StatRow { label: "Public"; value: root.num(root.traffic.externalRps, " req/s"); url: root.links.dashboard }
          StatRow {
            label: "Server errors"
            value: root.num(root.traffic.errorRps, " req/s")
            alert: root.traffic.errorRps > 0
            url: root.links.dashboard
          }

          // from loki, traefik counters carry no client detail
          Column {
            width: parent.width
            visible: (root.clients.countries || []).length > 0
            spacing: Style.spacing.md

            PanelSeparator {}
            Row {
              width: parent.width
              spacing: Style.spacing.sm
              PanelSectionHeader { text: "Incoming" }
              Text {
                anchors.verticalCenter: parent.verticalCenter
                text: root.clients.window || ""
                color: Color.menu.text
                opacity: Style.emphasis.faint
                textFormat: Text.PlainText
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
              }
            }

            Grid {
              id: clientGrid
              width: parent.width
              columns: 4
              columnSpacing: Style.spacing.lg
              readonly property real cellWidth:
                (width - columnSpacing * (columns - 1)) / columns

              ClientList { width: clientGrid.cellWidth; title: "From"; rows: root.clients.countries || [] }
              ClientList { width: clientGrid.cellWidth; title: "Clients"; rows: root.clients.agents || [] }
              ClientList { width: clientGrid.cellWidth; title: "Asking for"; rows: root.clients.hosts || [] }
              ClientList { width: clientGrid.cellWidth; title: "How it went"; rows: root.clients.traffic || [] }
            }
          }

          PanelSeparator {}
          PanelSectionHeader { text: "Services" }
          StatRow {
            label: "Up"
            value: root.upCount + " / " + root.monitored.length
            url: root.links.homepage
          }
          StatRow {
            visible: root.asleepCount > 0
            label: "Asleep"
            value: root.asleepCount
            url: root.links.homepage
          }
          StatRow {
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
}

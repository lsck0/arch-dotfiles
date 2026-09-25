import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Homelab health from homelab-status.py, which derives the fleet and every link from the homelab source.
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
  // The four incoming lists, as on the TRMNL dashboard.
  property var clients: ({})

  // Rolling history of host CPU% and memory% for the panel sparklines (newest last, capped).
  property var cpuHist: []
  property var memHist: []
  function _push(arr, v) { var a = arr.slice(); a.push(v); if (a.length > 60) a.shift(); return a }

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
          root.clients = s.clients || {}
          root.cpuHist = root._push(root.cpuHist, Number(root.host.cpuPct) || 0)
          root.memHist = root._push(root.memHist, (Number(root.host.memTotalGb) || 0) > 0
            ? (Number(root.host.memUsedGb) || 0) / Number(root.host.memTotalGb) * 100 : 0)
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
      // Neon halo while the fleet is reporting problems.
      layer.enabled: Style.fx.glow > 0 && root.ok && root.problemCount > 0
      layer.effect: MultiEffect {
        shadowEnabled: true
        shadowColor: Color.urgent
        shadowBlur: 1.0
        shadowVerticalOffset: 0
        shadowHorizontalOffset: 0
        blurMax: Style.fx.glowRadius
        autoPaddingEnabled: true
      }
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
      layer.effect: MultiEffect {
        shadowEnabled: true
        shadowColor: Color.urgent
        shadowBlur: 1.0
        shadowVerticalOffset: 0
        shadowHorizontalOffset: 0
        blurMax: Style.fx.glowRadius
        autoPaddingEnabled: true
      }
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

  // System.qml's label/value row, clickable: the hover fill bleeds past the column edge so the text stays aligned with the section headers.
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

  // One of the four incoming lists: a caption, then a row per entry with a bar of its share of the largest row in the same list.
  component ClientList: Column {
    id: list
    property string title: ""
    property var rows: []
    spacing: 0

    Text {
      text: list.title
      color: Color.menu.text
      opacity: Style.emphasis.faint
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
          // the share bar, drawn behind the text rather than beside it: a separate track would cost width the column does not have
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          height: parent.height
          width: parent.width * Math.max(0, Math.min(100, entry.modelData.pct || 0)) / 100
          radius: Style.cornerRadius
          // Accent-tinted gauge track: reads as a terminal HUD share bar.
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

  // One titled grid of services.
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

            // * up or link-only (never checked), o asleep, red when down.
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

  // Big glowing hero numeral (a percentage) opening a section.
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
      layer.effect: MultiEffect {
        shadowEnabled: true
        shadowColor: parent.tint
        shadowBlur: 1.0
        shadowVerticalOffset: 0
        shadowHorizontalOffset: 0
        blurMax: Style.fx.glowRadius
        autoPaddingEnabled: true
      }
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

  // History sparkline + current-value bar gauge under a tracked label with a live readout.
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
    Row {
      width: mg.width
      visible: mg.label !== ""
      Text {
        width: parent.width * 0.5
        text: mg.label
        color: mg.tint
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        font.bold: true
        font.capitalization: Font.AllUppercase
        font.letterSpacing: Style.headerTracking
      }
      Text {
        width: parent.width * 0.5
        horizontalAlignment: Text.AlignRight
        text: mg.readout
        color: mg.tint
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        font.letterSpacing: Style.displayTracking
      }
    }
    Sparkline { width: mg.width; height: Style.space(34); values: mg.history; minValue: 0; maxValue: mg.maxValue; color: mg.tint }
    BarGauge { width: mg.width; height: Style.spacing.md; segments: 24; value: mg.fraction; color: mg.tint }
  }

  // Compact tracked label + readout over a single HUD gauge, for ratios with no history.
  component GaugeRow: Column {
    id: gr
    property string label: ""
    property string readout: ""
    property real fraction: 0
    property color tint: Color.accent
    width: parent ? parent.width : 0
    spacing: Style.spacing.xxs
    Row {
      width: gr.width
      Text {
        width: parent.width * 0.5
        text: gr.label
        color: gr.tint
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        font.bold: true
        font.capitalization: Font.AllUppercase
        font.letterSpacing: Style.headerTracking
      }
      Text {
        width: parent.width * 0.5
        horizontalAlignment: Text.AlignRight
        text: gr.readout
        color: gr.tint
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        font.letterSpacing: Style.displayTracking
      }
    }
    BarGauge { width: gr.width; height: Style.spacing.md; segments: 24; value: gr.fraction; color: gr.tint }
  }

  HoverPanel {
    id: panel
    bar: root.bar
    moduleName: root.moduleName
    anchorWidget: root
    // Terminal-window title strip, rendered by the shared card.
    title: "Homelab"
    implicitWidth: Style.panelWidth.wide + Style.shadowOffset
    implicitHeight: Math.min(Style.space(880), content.implicitHeight + padding * 2) + Style.shadowOffset

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

      // Top headroom so the overlaid title strip never covers the first row.
      Item { width: 1; height: Style.spacing.xl }

      // ---- unreachable ------------------------------------------------------
      Row_ {
        visible: !root.ok
        label: "Status"
        value: !root.received ? "Connecting..." : root.error === "source" ? "No homelab checkout" : "Unreachable"
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
        // Big glowing CPU hero, live secondary readouts flush right.
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
            Row_ {
              label: "Memory"
              value: root.num(root.host.memUsedGb) + " / " + root.num(root.host.memTotalGb, " GB")
              url: root.links.proxmox
            }
            Row_ { label: "Temperature"; value: root.num(root.host.tempC, "°C"); url: root.links.proxmox }
            Row_ { label: "Uptime"; value: root.num(root.host.uptimeH, " h"); url: root.links.proxmox }
          }
        }
        MetricGraph { label: "Usage"; readout: root.num(root.host.cpuPct, "%"); history: root.cpuHist; fraction: (Number(root.host.cpuPct) || 0) / 100 }
        MetricGraph {
          label: "Memory"
          readout: (Number(root.host.memTotalGb) || 0) > 0 ? Math.round((Number(root.host.memUsedGb) || 0) / Number(root.host.memTotalGb) * 100) + "%" : "0%"
          history: root.memHist
          fraction: (Number(root.host.memTotalGb) || 0) > 0 ? (Number(root.host.memUsedGb) || 0) / Number(root.host.memTotalGb) : 0
        }

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
        // Capacity, disk health, and flash wear as HUD gauges.
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

        // ---- incoming ------------------------------------------------------- Who reached the lab from the internet, which is the one thing Prometheus cannot answer: its Traefik counters carry no client detail, so these come from the access log through Loki.
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

    // HUD corner brackets over the panel.
    HudFrame {}
  }
}

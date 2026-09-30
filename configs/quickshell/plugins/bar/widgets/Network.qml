import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "network"

  property string homeVpnState: "off"
  property string protonVpnState: "off"
  property string torState: "off"
  property bool anonymousSocksOn: false
  property bool anonymousNetworkPersonaOn: false
  property bool btPowered: false
  property bool wifiOn: true
  property bool offlineModeOn: false

  property bool detailsConnected: false
  property string connectivity: "unknown"
  readonly property bool reallyOnline: connectivity === "full"
  property string detailsDevice: ""
  property string detailsSsid: ""
  property string detailsIp4: ""
  property string detailsMac: ""
  property int detailsRxKbps: 0
  property int detailsTxKbps: 0

  property var rxHist: []
  property var txHist: []

  property var wifiNetworks: []
  property string connectingSsid: ""
  property string connectError: ""

  function fmtSpeed(kbps) {
    if (kbps >= 1024)
      return (Math.round(kbps / 1024 * 10) / 10) + " MB/s"
    return kbps + " KB/s"
  }

  implicitWidth: trigger.implicitWidth + Style.bar.itemPaddingX * 2
  implicitHeight: barSize

  function refreshAll() {
    homeVpnProc.running = true
    protonVpnProc.running = true
    torProc.running = true
    anonymousSocksProc.running = true
    anonymousNetworkPersonaProc.running = true
    btProc.running = true
    wifiProc.running = true
    rfkillProc.running = true
    if (!detailsProc.running) detailsProc.running = true
  }

  function refreshWifiList(rescan) {
    wifiScanProc.command = rescan
      ? [Paths.barWidget("network-wifi-scan.sh"), "rescan"]
      : [Paths.barWidget("network-wifi-scan.sh")]
    if (!wifiScanProc.running) wifiScanProc.running = true
  }

  function connectTo(ssid, password) {
    root.connectingSsid = ssid
    root.connectError = ""
    connectProc.command = password
      ? [Paths.barWidget("network-wifi-connect.sh"), ssid, password]
      : [Paths.barWidget("network-wifi-connect.sh"), ssid]
    connectProc.running = true
  }

  // toggles are detached and slow, so re-read a few times
  Timer {
    id: toggleSettle
    interval: 600
    repeat: true
    property int ticks: 0
    onTriggered: {
      root.refreshAll()
      ticks++
      if (ticks >= 4) stop()
    }
  }

  function afterToggle() {
    toggleSettle.ticks = 0
    toggleSettle.restart()
  }

  function toggleHomeVpn() { Quickshell.execDetached([Paths.toggle("toggle-vpn.sh"), "toggle"]); afterToggle() }
  function toggleProtonVpn() { Quickshell.execDetached([Paths.toggle("toggle-protonvpn.sh"), "toggle"]); afterToggle() }
  function toggleTor() { Quickshell.execDetached([Paths.toggle("toggle-tor.sh"), "toggle"]); afterToggle() }
  // exit verification can outlast afterToggle, so refresh on exit
  function toggleAnonymousSocks() {
    if (!anonymousSocksToggleProc.running) anonymousSocksToggleProc.running = true
    afterToggle()
  }
  Process {
    id: anonymousSocksToggleProc
    command: [Paths.toggle("toggle-anonymous-socks.sh"), "toggle"]
    onExited: root.afterToggle()
  }
  function toggleAnonymousNetworkPersona() { Quickshell.execDetached([Paths.toggle("toggle-anonymous-network-persona.sh"), "toggle"]); afterToggle() }
  function toggleBluetooth() { Quickshell.execDetached([Paths.toggle("toggle-bluetooth.sh"), "toggle"]); afterToggle() }
  function toggleWifi() { Quickshell.execDetached([Paths.toggle("toggle-wifi.sh"), "toggle"]); afterToggle() }
  function toggleOfflineMode() { Quickshell.execDetached([Paths.toggle("toggle-offline.sh"), "toggle"]); afterToggle() }

  Process {
    id: homeVpnProc
    command: [Paths.toggle("toggle-vpn.sh"), "get"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.homeVpnState = String(text || "off").trim() }
  }
  Process {
    id: protonVpnProc
    command: [Paths.toggle("toggle-protonvpn.sh"), "get"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.protonVpnState = String(text || "off").trim() }
  }
  Process {
    id: torProc
    command: [Paths.toggle("toggle-tor.sh"), "get"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.torState = String(text || "off").trim() }
  }
  Process {
    id: anonymousSocksProc
    command: [Paths.toggle("toggle-anonymous-socks.sh"), "get"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.anonymousSocksOn = String(text || "").trim() === "on" }
  }
  Process {
    id: anonymousNetworkPersonaProc
    command: [Paths.toggle("toggle-anonymous-network-persona.sh"), "get"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.anonymousNetworkPersonaOn = String(text || "").trim() === "on" }
  }
  Process {
    id: btProc
    command: [Paths.toggle("toggle-bluetooth.sh"), "get"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.btPowered = String(text || "").trim() === "on" }
  }
  Process {
    id: wifiProc
    command: [Paths.toggle("toggle-wifi.sh"), "get"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.wifiOn = String(text || "").trim() === "on" }
  }
  Process {
    id: rfkillProc
    command: [Paths.toggle("toggle-offline.sh"), "get"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.offlineModeOn = String(text || "").trim() === "on" }
  }
  Process {
    id: detailsProc
    command: [Paths.barWidget("network-details.sh")]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var d = JSON.parse(text || "{}")
          root.detailsConnected = !!d.connected
          root.connectivity = d.connectivity || "unknown"
          root.detailsDevice = d.device || ""
          root.detailsSsid = d.ssid || ""
          root.detailsIp4 = d.ip4 || ""
          root.detailsMac = d.mac || ""
          root.detailsRxKbps = d.rxKbps || 0
          root.detailsTxKbps = d.txKbps || 0
          root.rxHist = Util.historyPush(root.rxHist, root.detailsRxKbps)
          root.txHist = Util.historyPush(root.txHist, root.detailsTxKbps)
        } catch (e) {}
      }
    }
  }
  Process {
    id: wifiScanProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try { root.wifiNetworks = JSON.parse(text || "[]") } catch (e) {}
      }
    }
  }
  Process {
    id: connectProc
    stdout: StdioCollector { waitForEnd: true }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        if (text && text.trim() !== "") root.connectError = text.trim()
      }
    }
    onExited: function(exitCode) {
      root.connectingSsid = ""
      if (exitCode === 0) {
        root.connectError = ""
        Qt.callLater(function() { root.refreshWifiList(false); root.refreshAll() })
      }
    }
  }

  Process {
    id: nmMonitorProc
    running: true
    command: ["nmcli", "monitor"]
    stdout: SplitParser {
      splitMarker: "\n"
      onRead: nmDebounce.restart()
    }
    // exits when networkmanager restarts
    onExited: nmRestartTimer.restart()
  }

  // one nm change emits several lines
  Timer {
    id: nmDebounce
    interval: 400
    onTriggered: root.refreshAll()
  }

  Timer {
    id: nmRestartTimer
    interval: 5000
    onTriggered: nmMonitorProc.running = true
  }

  // fallback poll
  Timer {
    interval: 30000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refreshAll()
  }

  readonly property bool onEthernet: detailsDevice.indexOf("en") === 0 || detailsDevice.indexOf("eth") === 0
  readonly property string statusIcon: {
    if (offlineModeOn) return "\u{f072}"                                  // fa-plane
    if (homeVpnState === "on" || protonVpnState === "on") return "\u{f023}" // fa-lock
    if (!detailsConnected || connectivity === "none") return "\u{f0319}"  // md-lan_disconnect
    if (connectivity === "limited" || connectivity === "portal") return "\u{f071}" // fa-warning
    return onEthernet ? "\u{f0318}" : "\u{f1eb}"                         // md-lan_connect / fa-wifi
  }
  readonly property string connectivityLabel: {
    switch (connectivity) {
    case "full": return "Online"
    case "limited": return "No internet"
    case "portal": return "Captive portal"
    case "none": return "Offline"
    default: return "Unknown"
    }
  }

  Rectangle {
    anchors.fill: parent
    radius: Style.cornerRadius
    color: hoverArea.containsMouse ? Style.hoverFill : "transparent"
    Behavior on color { ColorAnimation { duration: 100 } }
  }

  Row {
    id: trigger
    anchors.centerIn: parent
    spacing: Style.spacing.xs

    Text {
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      text: root.statusIcon
      color: (root.homeVpnState === "on" || root.protonVpnState === "on" || root.torState === "on")
        ? Color.accent
        : (root.bar ? root.bar.barForeground : Color.foreground)
      font.family: root.bar ? root.bar.iconFontFamily : Style.font.iconFamily
      font.pixelSize: Style.font.icon
      layer.enabled: Style.fx.glow > 0 && (root.homeVpnState === "on" || root.protonVpnState === "on" || root.torState === "on")
      layer.effect: Glow {}
    }
  }

  MouseArea {
    id: hoverArea
    anchors.fill: parent
    hoverEnabled: true
    onEntered: if (root.bar) root.bar.hoverOpen(root.moduleName)
    onExited: if (root.bar) root.bar.hoverTriggerExit(root.moduleName)
  }

  HoverPanel {
    id: panel
    bar: root.bar
    moduleName: root.moduleName
    anchorWidget: root
    onOpened: { root.refreshAll(); root.refreshWifiList(false) }
    // wifi password input needs keyboard
    acceptsKeyboard: true
    title: "NETWORK"
    implicitWidth: Style.panelWidth.normal
    implicitHeight: content.implicitHeight + padding * 2 + titleInset

    Column {
      id: content
      width: parent.width
      spacing: Style.spacing.sm

      component ToggleRow: PanelRow {
        width: content.width
        stateMarker: glyph === ""
      }

      component DetailRow: Row {
        id: detailRow
        property string label: ""
        property string value: ""
        property color valueColor: Color.menu.text
        property int valueElide: Text.ElideNone
        width: content.width
        Text {
          width: detailRow.width * 0.35
          text: detailRow.label
          color: Color.menu.text
          font.pixelSize: Style.font.caption
          font.family: Style.font.family
        }
        Text {
          width: detailRow.width * 0.65
          horizontalAlignment: Text.AlignRight
          text: detailRow.value
          color: detailRow.valueColor
          elide: detailRow.valueElide
          font.pixelSize: Style.font.caption
          font.family: Style.font.family
        }
      }

      PanelSectionHeader {
        visible: root.detailsConnected
        text: "DETAILS"
      }
      Column {
        width: content.width
        spacing: Style.spacing.xs
        visible: root.detailsConnected
        DetailRow {
          label: "Status"
          value: root.connectivityLabel + (root.onEthernet ? "  ·  LAN" : "  ·  Wi-Fi")
          valueColor: root.reallyOnline ? Color.menu.text : Color.menu.selectedText
        }
        DetailRow {
          label: "Device"
          value: root.detailsDevice + (root.detailsSsid ? " (" + root.detailsSsid + ")" : "")
          valueElide: Text.ElideLeft
        }
        DetailRow { label: "IP"; value: root.detailsIp4 || "--" }
        DetailRow { label: "MAC"; value: root.detailsMac || "--" }
        DetailRow { label: "Speed"; value: "↓" + root.fmtSpeed(root.detailsRxKbps) + "  ↑" + root.fmtSpeed(root.detailsTxKbps) }
      }
      PanelSeparator {
        visible: root.detailsConnected
      }
      PanelSectionHeader { visible: root.detailsConnected; text: "THROUGHPUT" }

      Column {
        visible: root.detailsConnected
        width: content.width
        spacing: Style.spacing.xs

        Row {
          spacing: Style.spacing.xxs
          Text {
            anchors.bottom: parent.bottom
            text: root.fmtSpeed(root.detailsRxKbps)
            color: Color.accent
            font.family: Style.font.family
            font.pixelSize: Math.round(Style.font.display * 1.1)
            font.bold: true
            font.letterSpacing: Style.displayTracking
            layer.enabled: Style.fx.glow > 0
            layer.effect: Glow {}
          }
        }

        Row {
          width: parent.width
          Text {
            width: parent.width * 0.5
            text: "# DOWN"
            color: Color.accent
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            font.bold: true
            font.capitalization: Font.AllUppercase
            font.letterSpacing: Style.headerTracking
          }
          Text {
            width: parent.width * 0.5
            horizontalAlignment: Text.AlignRight
            text: root.fmtSpeed(root.detailsRxKbps)
            color: Color.menu.text
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            font.letterSpacing: Style.displayTracking
          }
        }
        Sparkline { width: parent.width; height: Style.space(30); values: root.rxHist; minValue: 0; maxValue: 0; color: Color.accent }

        Row {
          width: parent.width
          Text {
            width: parent.width * 0.5
            text: "# UP"
            color: Color.accent
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            font.bold: true
            font.capitalization: Font.AllUppercase
            font.letterSpacing: Style.headerTracking
          }
          Text {
            width: parent.width * 0.5
            horizontalAlignment: Text.AlignRight
            text: root.fmtSpeed(root.detailsTxKbps)
            color: Color.menu.text
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            font.letterSpacing: Style.displayTracking
          }
        }
        Sparkline { width: parent.width; height: Style.space(30); values: root.txHist; minValue: 0; maxValue: 0; color: Color.menu.text }
      }

      PanelSeparator {
        visible: root.detailsConnected
      }
      PanelSectionHeader { text: "WI-FI NETWORKS" }

      Column {
        width: content.width
        spacing: Style.spacing.xxs

        Repeater {
          model: root.wifiNetworks
          delegate: Column {
            required property var modelData
            width: content.width

            Rectangle {
              id: netRow
              property bool pendingConnect: false
              width: parent.width
              height: Style.row.list
              radius: Style.cornerRadius
              color: modelData.active ? Color.menu.selectedBackground : (netMouse.containsMouse ? Style.hoverFill : "transparent")

              Text {
                id: netIcon
                anchors.left: parent.left
                anchors.leftMargin: Style.spacing.md
                anchors.verticalCenter: parent.verticalCenter
                text: modelData.active ? "*" : (modelData.secure ? "\u{f023}" : "\u{f1eb}")
                color: modelData.active ? Color.menu.selectedText : Color.menu.text
                font.pixelSize: Style.font.caption
                font.family: Style.font.iconFamily
                layer.enabled: Style.fx.glow > 0 && modelData.active
                layer.effect: Glow {}
              }
              Text {
                anchors.left: netIcon.right
                anchors.leftMargin: Style.spacing.sm
                anchors.right: netSignal.left
                anchors.rightMargin: Style.spacing.sm
                anchors.verticalCenter: parent.verticalCenter
                text: modelData.ssid
                color: modelData.active ? Color.menu.selectedText : Color.menu.text
                font.pixelSize: Style.font.body
                font.family: Style.font.family
                elide: Text.ElideRight
              }
              Text {
                id: netSignal
                anchors.right: parent.right
                anchors.rightMargin: Style.spacing.md
                anchors.verticalCenter: parent.verticalCenter
                text: modelData.signal + "%"
                color: Color.menu.text
                opacity: modelData.active ? 1 : Style.emphasis.faint
                font.pixelSize: Style.font.caption
                font.family: Style.font.family
              }

              MouseArea {
                id: netMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                  if (modelData.active) return
                  if (modelData.secure) {
                    netRow.pendingConnect = !netRow.pendingConnect
                  } else {
                    root.connectTo(modelData.ssid, "")
                  }
                }
              }
            }

            Row {
              visible: netRow.pendingConnect && !modelData.active
              width: parent.width
              spacing: Style.spacing.xs
              leftPadding: Style.spacing.lg

              Rectangle {
                width: parent.width - parent.leftPadding - connectButton.width - parent.spacing
                height: Style.row.control
                radius: Style.cornerRadius
                color: Style.normalFill
                border.width: pwInput.activeFocus ? 1 : 0
                border.color: Color.accent

                TextInput {
                  id: pwInput
                  anchors.fill: parent
                  anchors.leftMargin: Style.spacing.sm
                  anchors.rightMargin: Style.spacing.sm
                  verticalAlignment: TextInput.AlignVCenter
                  echoMode: TextInput.Password
                  color: Color.menu.text
                  font.pixelSize: Style.font.caption
                  font.family: Style.font.family
                  onAccepted: { root.connectTo(modelData.ssid, text); netRow.pendingConnect = false }
                }
              }
              Rectangle {
                id: connectButton
                width: Style.space(70)
                height: Style.row.control
                radius: Style.cornerRadius
                color: Style.selectedFillFor(Color.menu.text, Color.accent)
                Text {
                  anchors.centerIn: parent
                  text: root.connectingSsid === modelData.ssid ? "..." : "Connect"
                  color: Color.accent
                  font.pixelSize: Style.font.caption
                  font.family: Style.font.family
                }
                MouseArea {
                  anchors.fill: parent
                  cursorShape: Qt.PointingHandCursor
                  onClicked: { root.connectTo(modelData.ssid, pwInput.text); netRow.pendingConnect = false }
                }
              }
            }
          }
        }

        Text {
          visible: root.wifiNetworks.length === 0
          text: "No networks found, scanning..."
          color: Color.menu.text
          opacity: Style.emphasis.faint
          font.pixelSize: Style.font.caption
          font.family: Style.font.family
        }

        Text {
          visible: root.connectError !== ""
          width: content.width
          wrapMode: Text.Wrap
          text: root.connectError
          color: Color.urgent
          font.pixelSize: Style.font.caption
          font.family: Style.font.family
        }
      }

      PanelSeparator {}
      PanelSectionHeader { text: "TUNNELS" }
      ToggleRow { label: "ProtonVPN"; on: root.protonVpnState === "on"; onActivated: root.toggleProtonVpn() }
      ToggleRow { label: "Homelab VPN"; on: root.homeVpnState === "on"; onActivated: root.toggleHomeVpn() }
      ToggleRow { label: "Tor Network"; on: root.torState === "on"; onActivated: root.toggleTor() }
      ToggleRow { label: "Anonymous SOCKS"; on: root.anonymousSocksOn; onActivated: root.toggleAnonymousSocks() }
      ToggleRow { label: "Anonymous Network Persona"; on: root.anonymousNetworkPersonaOn; onActivated: root.toggleAnonymousNetworkPersona() }

      PanelSeparator {}
      PanelSectionHeader { text: "RADIOS" }
      ToggleRow { label: "Wi-Fi"; on: root.wifiOn; onActivated: root.toggleWifi() }
      ToggleRow { label: "Bluetooth"; on: root.btPowered; onActivated: root.toggleBluetooth() }
      ToggleRow { label: "Offline mode"; on: root.offlineModeOn; onActivated: root.toggleOfflineMode() }

      PanelSeparator {}
      PanelSectionHeader { text: "TOOLS" }
      ToggleRow {
        label: "Internet speed test"
        glyph: "\u{f04c5}"
        onActivated: {
          if (root.bar) root.bar.closePanel(root.moduleName)
          Quickshell.execDetached(Paths.ipcCall("shell", "summon", "panel.speedtest", "{}"))
        }
      }

      ToggleRow {
        visible: root.detailsConnected && !root.onEthernet
        label: "Share Wi-Fi (QR)"
        glyph: "\u{f0432}"
        onActivated: {
          if (root.bar) root.bar.closePanel(root.moduleName)
          Quickshell.execDetached(Paths.ipcCall("shell", "summon", "panel.wifiqr",
            JSON.stringify({ iface: root.detailsDevice, ssid: root.detailsSsid })))
        }
      }
    }
  }
}

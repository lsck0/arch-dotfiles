pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "network"
  barPriority: 75
  hoverPanel: true
  hoverFill: true
  hoverCursor: Qt.ArrowCursor

  // the network toggles' status records (scripts/toggles/status.nu), by name
  property var toggles: ({})
  function toggleState(name, fallback) { return toggles[name] ? toggles[name].state : fallback }
  function toggleOn(name) { return toggleState(name, "off") === "on" }
  function toggleAvailable(name) { return !!toggles[name] && toggles[name].available }
  function toggleLabel(name, fallback) { return toggles[name] && toggles[name].label ? toggles[name].label : fallback }
  readonly property var toggleNames: ["route", "vpn", "anonymous-socks", "bluetooth", "wifi", "ethernet", "mobile", "firewall",
    "trust-network", "portal"]

  readonly property string homeVpnState: toggleState("vpn", "off")
  readonly property string route: toggleState("route", "direct")
  readonly property string protonVpnState: route === "proton" ? "on" : "off"
  readonly property string torState: route === "tor" ? "on" : "off"
  readonly property bool anonymousSocksOn: toggleOn("anonymous-socks")
  readonly property bool btPowered: toggleOn("bluetooth")
  readonly property bool wifiOn: toggleState("wifi", "on") === "on"
  readonly property bool ethernetOn: toggleOn("ethernet")
  readonly property bool mobileOn: toggleOn("mobile")
  readonly property bool hasMobile: toggleAvailable("mobile")
  readonly property bool offlineModeOn: route === "offline"
  readonly property string firewallState: toggleState("firewall", "")
  readonly property bool homelabAvailable: toggleAvailable("vpn")
  readonly property bool trustedNetwork: toggleOn("trust-network")
  readonly property bool trustAvailable: toggleAvailable("trust-network")
  readonly property bool portalOpen: toggleOn("portal")
  readonly property bool portalAvailable: toggleAvailable("portal")

  property bool detailsConnected: false
  property string connectivity: "unknown"
  readonly property bool reallyOnline: connectivity === "full" || (detailsConnected && connectivity === "unknown")
  property string detailsDevice: ""
  property string detailsConnection: ""
  property string detailsIp4: ""
  property string detailsMac: ""
  property int detailsRxKbps: 0
  property int detailsTxKbps: 0

  property var rxHist: []
  property var txHist: []

  property var wifiNetworks: []
  property string connectingSsid: ""
  property string connectError: ""
  property bool passwordFocused: false

  function fmtSpeed(kbps) {
    if (kbps >= 1024)
      return (Math.round(kbps / 1024 * 10) / 10) + " MB/s"
    return kbps + " KB/s"
  }

  implicitWidth: trigger.implicitWidth + Style.bar.itemPaddingX * 2
  implicitHeight: barSize

  readonly property int refreshMinAgeMs: 60 * 1000
  property real lastRefreshMs: 0
  property real lastScanMs: 0

  function refreshAll() {
    lastRefreshMs = Date.now()
    togglesProc.run()
    if (!detailsProc.running) detailsProc.running = true
  }

  function refreshWifiList(rescan) {
    if (wifiScanProc.running) return
    if (rescan) lastScanMs = Date.now()
    wifiScanProc.command = rescan
      ? [Paths.barWidget("network-wifi-scan.nu"), "rescan"]
      : [Paths.barWidget("network-wifi-scan.nu")]
    wifiScanProc.running = true
  }

  function panelOpened() {
    var now = Date.now()
    if (now - lastRefreshMs >= refreshMinAgeMs) refreshAll()
    else if (!detailsProc.running) detailsProc.running = true
    refreshWifiList(now - lastScanMs >= refreshMinAgeMs)
  }

  function connectTo(ssid, password) {
    if (connectProc.running) return
    root.connectingSsid = ssid
    root.connectError = ""
    connectProc.command = [Paths.barWidget("network-wifi-connect.nu"), ssid]
    connectProc.stdinEnabled = true
    connectProc.running = true
    connectProc.write((password || "") + "\n")
    connectProc.stdinEnabled = false
  }

  function runToggle(script) { Quickshell.execDetached([Paths.toggle(script), "toggle"]) }
  function toggleHomeVpn() { runToggle("toggle-vpn.nu") }
  function toggleAnonymousSocks() { runToggle("toggle-anonymous-socks.nu") }
  function toggleBluetooth() { runToggle("toggle-bluetooth.nu") }
  function toggleWifi() { runToggle("toggle-wifi.nu") }
  function toggleEthernet() { runToggle("toggle-ethernet.nu") }
  function toggleMobile() { runToggle("toggle-mobile.nu") }
  function toggleTrustNetwork() { runToggle("toggle-trust-network.nu") }
  function togglePortal() { runToggle("toggle-portal.nu") }
  function setRoute(state) { Quickshell.execDetached([Paths.toggle("toggle-route.nu"), "set", state]) }
  function setFirewall(state) { Quickshell.execDetached([Paths.toggle("toggle-firewall.nu"), "set", state]) }

  readonly property var routeModes: [
    { value: "direct", label: "DIRECT" },
    { value: "proton", label: "PROTON" },
    { value: "tor", label: "TOR" },
    { value: "offline", label: "OFFLINE" }
  ]
  readonly property var firewallModes: [
    { value: "permissive", label: "PERMISSIVE" },
    { value: "default", label: "DEFAULT" },
    { value: "restrictive", label: "RESTRICTIVE" }
  ]

  JsonProcess {
    id: togglesProc
    command: [Paths.toggle("status.nu")].concat(root.toggleNames)
    onParsed: function (data) {
      var next = {}
      for (let i = 0; i < data.length; i++) next[data[i].name] = data[i]
      root.toggles = next
    }
  }
  Component.onCompleted: refreshAll()
  JsonProcess {
    id: detailsProc
    command: [Paths.barWidget("network-details.nu")]
    onParsed: function(d) {
      root.detailsConnected = !!d.connected
      root.connectivity = d.connectivity || "unknown"
      root.detailsDevice = d.device || ""
      root.detailsConnection = d.connection || ""
      root.detailsIp4 = d.ip4 || ""
      root.detailsMac = d.mac || ""
      root.detailsRxKbps = d.rxKbps || 0
      root.detailsTxKbps = d.txKbps || 0
      root.rxHist = Util.historyPush(root.rxHist, root.detailsRxKbps)
      root.txHist = Util.historyPush(root.txHist, root.detailsTxKbps)
    }
  }
  JsonProcess {
    id: wifiScanProc
    onParsed: function(data) { root.wifiNetworks = data }
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
    command: ["setpriv", "--pdeathsig", "TERM", "nmcli", "monitor"]
    Component.onDestruction: running = false
    stdout: SplitParser {
      splitMarker: "\n"
      onRead: nmDebounce.restart()
    }
    onExited: nmRestartTimer.restart()
  }

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

  Connections {
    target: ToggleEvents
    function onChanged(script) { if (root.toggleNames.indexOf(script.replace(/^toggle-(.*)\.nu$/, "$1")) >= 0) nmDebounce.restart() }
  }

  // rxKbps/txKbps need continuous sampling; nmcli monitor only emits on connectivity changes, not throughput
  Timer {
    interval: 2000
    running: panel.visible
    repeat: true
    onTriggered: if (!detailsProc.running) detailsProc.running = true
  }

  readonly property bool onEthernet: detailsDevice.indexOf("en") === 0 || detailsDevice.indexOf("eth") === 0
  readonly property string statusIcon: {
    if (offlineModeOn) return "\u{f072}"
    if (homeVpnState === "on" || protonVpnState === "on") return "\u{f023}"
    if (!detailsConnected || connectivity === "none") return "\u{f0319}"
    if (connectivity === "limited" || connectivity === "portal") return "\u{f071}"
    return onEthernet ? "\u{f0318}" : "\u{f1eb}"
  }
  readonly property string connectivityLabel: {
    switch (connectivity) {
    case "full": return "Online"
    case "limited": return "No internet"
    case "portal": return "Captive portal"
    case "none": return "Offline"
    default: return root.detailsConnected ? "Online" : "Unknown"
    }
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
        ? Colors.accentText
        : (root.bar ? root.bar.barForeground : Colors.foreground)
      font.family: root.bar ? root.bar.iconFontFamily : Style.font.iconFamily
      font.pixelSize: Style.font.icon
      layer.enabled: Style.fx.glow > 0 && (root.homeVpnState === "on" || root.protonVpnState === "on" || root.torState === "on")
      layer.effect: Glow {}
    }
  }

  HoverPanel {
    id: panel
    anchorWidget: root
    onOpened: root.panelOpened()
    pinned: root.passwordFocused
    acceptsKeyboard: true
    title: "NETWORK"
    implicitWidth: Style.panelWidth.normal

    Column {
      id: content
      width: parent.width
      spacing: Style.spacing.xs

      component ToggleRow: PanelRow {
        width: content.width
        stateMarker: glyph === ""
      }

      PanelSectionHeader {
        visible: root.detailsConnected
        text: "DETAILS"
      }
      Column {
        width: content.width
        spacing: Style.spacing.xs
        visible: root.detailsConnected
        StatRow {
          label: "Status"
          value: root.connectivityLabel + (root.onEthernet ? " :: LAN" : " :: Wi-Fi")
          valueColor: root.reallyOnline ? Colors.menu.text : Colors.accentText
        }
        StatRow {
          label: "Device"
          value: root.detailsDevice + (root.detailsConnection ? " (" + root.detailsConnection + ")" : "")
          valueElide: Text.ElideLeft
        }
        StatRow { label: "IP"; value: root.detailsIp4 || "--" }
        StatRow { label: "MAC"; value: root.detailsMac || "--" }
        StatRow { label: "Speed"; value: "rx " + root.fmtSpeed(root.detailsRxKbps) + "  tx " + root.fmtSpeed(root.detailsTxKbps) }
      }
      PanelSeparator {
        visible: root.detailsConnected
      }
      PanelSectionHeader { visible: root.detailsConnected; text: "THROUGHPUT" }

      Column {
        visible: root.detailsConnected
        width: content.width
        spacing: Style.spacing.xs

        Hero {
          readonly property bool txLeads: root.detailsTxKbps > root.detailsRxKbps

          value: root.fmtSpeed(txLeads ? root.detailsTxKbps : root.detailsRxKbps)
          unit: txLeads ? "tx" : "rx"
          live: true
        }

        StatRow { label: "rx"; value: root.fmtSpeed(root.detailsRxKbps) }
        Sparkline { width: parent.width; height: Style.space(30); values: root.rxHist; minValue: 0; maxValue: 0; color: Colors.accent }

        StatRow { label: "tx"; value: root.fmtSpeed(root.detailsTxKbps) }
        Sparkline { width: parent.width; height: Style.space(30); values: root.txHist; minValue: 0; maxValue: 0; color: Colors.menu.text }
      }

      PanelSeparator {
        visible: root.detailsConnected && root.wifiOn
      }
      // with the radio off there is nothing to list: the RADIOS section turns it on
      PanelSectionHeader { visible: root.wifiOn; text: "WI-FI NETWORKS" }

      Column {
        visible: root.wifiOn
        width: content.width
        spacing: Style.spacing.xxs

        Repeater {
          model: root.wifiNetworks
          delegate: Column {
            id: wifiNet
            required property var modelData
            width: content.width

            Rectangle {
              id: netRow
              property bool pendingConnect: false
              width: parent.width
              height: Style.row.list
              radius: Style.shape.data
              color: wifiNet.modelData.active ? Colors.menu.selectedBackground
                : activeFocus ? Style.focusFillFor(Colors.foreground, Colors.accent)
                : netMouse.containsMouse ? Style.hoverFill : "transparent"

              activeFocusOnTab: !wifiNet.modelData.active
              Keys.onReturnPressed: netRow.activate()
              Keys.onEnterPressed: netRow.activate()
              Keys.onSpacePressed: netRow.activate()

              function activate() {
                if (wifiNet.modelData.active) return
                if (!wifiNet.modelData.secure) {
                  root.connectTo(wifiNet.modelData.ssid, "")
                  return
                }
                netRow.pendingConnect = !netRow.pendingConnect
                if (netRow.pendingConnect) Qt.callLater(pwInput.forceActiveFocus)
              }

              Text {
                id: netIcon
                anchors.left: parent.left
                anchors.leftMargin: Style.spacing.sm
                anchors.verticalCenter: parent.verticalCenter
                text: wifiNet.modelData.active ? "*" : (wifiNet.modelData.secure ? "\u{f023}" : "\u{f1eb}")
                color: wifiNet.modelData.active ? Colors.menu.selectedText : Colors.menu.text
                font.pixelSize: Style.font.caption
                font.family: Style.font.iconFamily
                layer.enabled: Style.fx.glow > 0 && wifiNet.modelData.active
                layer.effect: Glow {}
              }
              Text {
                // an access point picks its SSID: never markup
                textFormat: Text.PlainText
                anchors.left: netIcon.right
                anchors.leftMargin: Style.spacing.xs
                anchors.right: netSignal.left
                anchors.rightMargin: Style.spacing.xs
                anchors.verticalCenter: parent.verticalCenter
                text: wifiNet.modelData.ssid
                color: wifiNet.modelData.active ? Colors.menu.selectedText : Colors.menu.text
                font.pixelSize: Style.font.body
                font.family: Style.font.family
                elide: Text.ElideRight
              }
              Text {
                id: netSignal
                anchors.right: parent.right
                anchors.rightMargin: Style.spacing.sm
                anchors.verticalCenter: parent.verticalCenter
                text: wifiNet.modelData.signal + "%"
                color: wifiNet.modelData.active ? Colors.menu.text : Colors.textDim
                font.pixelSize: Style.font.caption
                font.family: Style.font.family
              }

              MouseArea {
                id: netMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: netRow.activate()
              }
            }

            Row {
              visible: netRow.pendingConnect && !wifiNet.modelData.active
              width: parent.width
              spacing: Style.spacing.xs
              leftPadding: Style.spacing.sm

              Rectangle {
                width: parent.width - parent.leftPadding - connectButton.width - parent.spacing
                height: Style.row.control
                radius: Style.shape.data
                color: Style.normalFill
                border.width: pwInput.activeFocus ? 1 : 0
                border.color: Colors.accent

                TextInput {
                  id: pwInput
                  onActiveFocusChanged: root.passwordFocused = activeFocus
                  Component.onDestruction: if (activeFocus) root.passwordFocused = false
                  anchors.fill: parent
                  anchors.leftMargin: Style.spacing.xs
                  anchors.rightMargin: Style.spacing.xs
                  verticalAlignment: TextInput.AlignVCenter
                  echoMode: TextInput.Password
                  color: Colors.menu.text
                  font.pixelSize: Style.font.caption
                  font.family: Style.font.family
                  onAccepted: { root.connectTo(wifiNet.modelData.ssid, text); netRow.pendingConnect = false }
                }
              }
              Rectangle {
                id: connectButton
                width: Style.space(70)
                height: Style.row.control
                radius: Style.shape.data
                color: Style.selectedFillFor(Colors.menu.text, Colors.accent)
                Text {
                  anchors.centerIn: parent
                  text: root.connectingSsid === wifiNet.modelData.ssid ? "..." : "Connect"
                  color: Colors.accentText
                  font.pixelSize: Style.font.caption
                  font.family: Style.font.family
                }
                MouseArea {
                  anchors.fill: parent
                  cursorShape: Qt.PointingHandCursor
                  onClicked: { root.connectTo(wifiNet.modelData.ssid, pwInput.text); netRow.pendingConnect = false }
                }
              }
            }
          }
        }

        Text {
          visible: root.wifiNetworks.length === 0 || wifiScanProc.running
          text: wifiScanProc.running ? "> SCANNING" : "> NOTHING HERE"
          color: Colors.textDim
          font.pixelSize: Style.font.caption
          font.family: Style.font.family
        }

        Text {
          textFormat: Text.PlainText
          visible: root.connectError !== ""
          width: content.width
          wrapMode: Text.Wrap
          text: root.connectError
          color: Colors.urgentText
          font.pixelSize: Style.font.caption
          font.family: Style.font.family
        }
      }

      PanelSeparator {}
      PanelSectionHeader { text: "FIREWALL" }
      ButtonGroup {
        width: content.width
        fill: true
        spacing: Style.spacing.xs
        fontSize: Style.font.caption
        options: root.firewallModes
        value: root.firewallState
        onChanged: function(state) { if (state !== root.firewallState) root.setFirewall(state) }
      }
      // home lifts the lockdown on this link: the gateway joins networkmanager's home_gateways
      ToggleRow { visible: root.trustAvailable; label: root.toggleLabel("trust-network", "Trusted network"); on: root.trustedNetwork; onActivated: root.toggleTrustNetwork() }
      // offered while NM reports a portal or one is open: tor and strict dot keep its login page out of reach
      ToggleRow {
        visible: root.portalAvailable && (root.connectivity === "portal" || root.portalOpen)
        label: root.toggleLabel("portal", "Captive portal")
        on: root.portalOpen
        onActivated: root.togglePortal()
      }

      PanelSeparator {}
      PanelSectionHeader { text: "ROUTE" }
      // the homelab sits beside the routes, not among them: wg0 carries only the lab subnets, so it adds to any route
      Row {
        width: content.width
        spacing: Style.spacing.xs

        ButtonGroup {
          width: parent.width - (homelabChip.visible ? homelabChip.width + parent.spacing : 0)
          fill: true
          spacing: Style.spacing.xs
          fontSize: Style.font.caption
          options: root.routeModes
          value: root.route
          onChanged: function(state) { if (state !== root.route) root.setRoute(state) }
        }

        Button {
          id: homelabChip
          visible: root.homelabAvailable
          variant: "chip"
          text: "+ HOMELAB"
          fontSize: Style.font.caption
          selected: root.homeVpnState === "on"
          onClicked: root.toggleHomeVpn()
        }
      }
      // the SOCKS pool listens on lo, beside any route
      ToggleRow { label: "Anonymous SOCKS"; on: root.anonymousSocksOn; onActivated: root.toggleAnonymousSocks() }

      PanelSeparator {}
      PanelSectionHeader { text: "RADIOS" }
      ToggleRow { label: "Wi-Fi"; on: root.wifiOn; onActivated: root.toggleWifi() }
      ToggleRow { label: "Ethernet"; on: root.ethernetOn; onActivated: root.toggleEthernet() }
      ToggleRow { visible: root.hasMobile; label: "Mobile"; on: root.mobileOn; onActivated: root.toggleMobile() }
      ToggleRow { label: "Bluetooth"; on: root.btPowered; onActivated: root.toggleBluetooth() }

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
            JSON.stringify({ iface: root.detailsDevice })))
        }
      }
    }
  }
}

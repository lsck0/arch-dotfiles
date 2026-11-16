pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

BarWidget {
  id: root

  component ToggleRow: PanelRow {
    width: parent ? parent.width : 0
    stateMarker: glyph === ""
  }

  // one toggle as a chip, lit while it is on
  component RadioChip: Button {
    property string toggle: ""
    variant: "chip"
    focusable: true
    selected: root.toggleOn(toggle)
    opacity: root.busyOpacity(toggle)
    onClicked: root.runToggle(toggle)
  }

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
  readonly property bool vpnOn: homeVpnState === "on" || route === "proton"
  // traffic leaves through a tunnel: the bar glyph takes the accent
  readonly property bool tunnelled: vpnOn || route === "tor"
  readonly property bool wifiOn: toggleState("wifi", "on") === "on"
  readonly property bool offlineModeOn: route === "offline"
  readonly property string firewallState: toggleState("firewall", "")
  readonly property bool portalOpen: toggleOn("portal")

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
  // a dense block lists thirty networks: the strongest few show, the rest behind "All networks"
  readonly property int wifiShownCountMax: 6
  property bool wifiShowAll: false
  readonly property var wifiShown: wifiShowAll ? wifiNetworks : wifiNetworks.slice(0, wifiShownCountMax)
  // the network last asked for; connectError is that attempt's failure and belongs to no other row
  property string connectSsid: ""
  readonly property string connectingSsid: connectProc.running ? connectSsid : ""
  property string connectError: ""
  property bool passwordFocused: false

  // network-details.nu counts KiB a second
  function speedText(kibPerSecond) { return Util.bytes(kibPerSecond * 1024) + "/s" }

  implicitWidth: trigger.implicitWidth + Style.bar.itemPaddingX * 2
  implicitHeight: Style.bar.sizeHorizontal

  readonly property int refreshMinAgeMs: 60 * 1000
  property real lastRefreshMs: 0
  property real lastScanMs: 0

  function refreshAll() {
    lastRefreshMs = Date.now()
    togglesProc.run()
    detailsProc.run()
  }

  function refreshWifiList(rescan) {
    if (wifiScanProc.running) return
    if (rescan) lastScanMs = Date.now()
    wifiScanProc.command = [Paths.barWidget("network-wifi-scan.nu")].concat(rescan ? ["rescan"] : [])
    wifiScanProc.running = true
  }

  function panelOpened() {
    var now = Date.now()
    wifiShowAll = false
    if (now - lastRefreshMs >= refreshMinAgeMs) refreshAll()
    else detailsProc.run()
    refreshWifiList(now - lastScanMs >= refreshMinAgeMs)
  }

  // identity (user@realm) only for a wpa-eap network: the script's second stdin line
  function connectTo(ssid, password, identity) {
    if (connectProc.running) return
    root.connectSsid = ssid
    root.connectError = ""
    connectProc.command = [Paths.barWidget("network-wifi-connect.nu"), ssid]
    connectProc.stdinEnabled = true
    connectProc.running = true
    connectProc.write((password || "") + "\n" + (identity || "") + "\n")
    connectProc.stdinEnabled = false
  }

  // a toggle started here that has not reported back (ToggleEvents) yet: dimmed but still readable (it is busy, not
  // disabled), and a press on it ignored rather than flipping it the same way twice; one that dies without reporting
  // is freed after busyMaxMs
  property var busyToggles: ({})
  readonly property int busyMaxMs: 5 * 60 * 1000
  function toggleBusy(name) { return busyToggles[name] === true }
  function busyOpacity(name) { return toggleBusy(name) ? Style.emphasis.dim : 1 }

  // scripts/toggles/toggle-<name>.nu, "toggle" unless a verb and value are given
  function runToggle(name, ...args) {
    if (toggleBusy(name)) return
    busyToggles = Util.mapSet(busyToggles, name, true)
    busyExpiry.restart()
    Quickshell.execDetached([Paths.toggle("toggle-" + name + ".nu")].concat(args.length ? args : ["toggle"]))
  }

  Timer {
    id: busyExpiry
    interval: root.busyMaxMs
    onTriggered: root.busyToggles = ({})
  }

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
    function onChanged(script) {
      var name = script.replace(/^toggle-(.*)\.nu$/, "$1")
      if (root.toggleBusy(name)) root.busyToggles = Util.mapWithout(root.busyToggles, name)
      if (root.toggleNames.indexOf(name) >= 0) nmDebounce.restart()
    }
  }

  // rxKbps/txKbps need continuous sampling; nmcli monitor only emits on connectivity changes, not throughput
  Timer {
    interval: 2000
    running: panel.visible
    repeat: true
    onTriggered: detailsProc.run()
  }

  readonly property bool onEthernet: detailsDevice.indexOf("en") === 0 || detailsDevice.indexOf("eth") === 0
  readonly property string statusIcon: {
    if (offlineModeOn) return "\u{f072}"
    // tor has its own glyph (md-incognito): the accent alone does not tell it from a vpn
    if (route === "tor") return "\u{f05f9}"
    if (vpnOn) return "\u{f023}"
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

    Label {
      anchors.verticalCenter: parent.verticalCenter
      text: root.statusIcon
      color: root.tunnelled ? Colors.accentText : Colors.bar.text
      icon: true
      font.pixelSize: Style.font.icon
      layer.enabled: Style.fx.glow > 0 && root.tunnelled
      layer.effect: Glow {}
    }
  }

  HoverPanel {
    id: panel
    anchorWidget: root
    onOpened: root.panelOpened()
    pinned: root.passwordFocused
    title: "NETWORK"
    implicitWidth: Style.panelWidth.normal

    Column {
      id: content
      width: parent.width
      spacing: Style.spacing.xs

      PanelSectionHeader { visible: root.detailsConnected; text: "DETAILS" }
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
      }
      PanelSeparator { visible: root.detailsConnected }
      PanelSectionHeader { visible: root.detailsConnected; text: "THROUGHPUT" }

      Column {
        visible: root.detailsConnected
        width: content.width
        spacing: Style.spacing.xs

        // one sample draws no line, only an empty box
        StatRow { label: "rx"; value: root.speedText(root.detailsRxKbps) }
        Sparkline { width: parent.width; height: Style.space(30); values: root.rxHist }

        StatRow { label: "tx"; value: root.speedText(root.detailsTxKbps) }
        Sparkline { width: parent.width; height: Style.space(30); values: root.txHist; color: Colors.menu.text }
      }

      PanelSeparator { visible: root.detailsConnected && root.wifiOn }
      // with the radio off there is nothing to list: the RADIOS section turns it on
      PanelSectionHeader { visible: root.wifiOn; text: "WI-FI NETWORKS" }

      Column {
        visible: root.wifiOn
        width: content.width
        spacing: Style.spacing.xxs

        Repeater {
          model: root.wifiShown
          delegate: Column {
            id: wifiNet
            required property var modelData
            width: content.width

            Rectangle {
              id: netRow
              property bool pendingConnect: false
              readonly property bool connecting: root.connectingSsid === wifiNet.modelData.ssid
              readonly property bool failed: root.connectError !== "" && root.connectSsid === wifiNet.modelData.ssid
              readonly property bool highlighted: wifiNet.modelData.active || activeFocus || netMouse.containsMouse
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

              function submit() {
                root.connectTo(wifiNet.modelData.ssid, pwInput.text, idInput.text)
                netRow.pendingConnect = false
              }

              function activate() {
                if (wifiNet.modelData.active) return
                // open, or saved: the profile's own secret; a wrong one fails into connectError, then this row's field shows
                if (!wifiNet.modelData.secure || (wifiNet.modelData.known && !netRow.pendingConnect && !netRow.failed)) {
                  root.connectTo(wifiNet.modelData.ssid, "")
                  return
                }
                netRow.pendingConnect = !netRow.pendingConnect
                if (netRow.pendingConnect) Qt.callLater(wifiNet.modelData.enterprise ? idInput.forceActiveFocus : pwInput.forceActiveFocus)
              }

              Label {
                id: netIcon
                anchors.left: parent.left
                anchors.leftMargin: Style.spacing.sm
                anchors.verticalCenter: parent.verticalCenter
                text: wifiNet.modelData.active ? "*" : (wifiNet.modelData.secure ? "\u{f023}" : "\u{f1eb}")
                color: wifiNet.modelData.active ? Colors.menu.selectedText : Colors.menu.text
                caption: true
                icon: true
                layer.enabled: Style.fx.glow > 0 && wifiNet.modelData.active
                layer.effect: Glow {}
              }
              Label {
                // an access point picks its SSID: never markup
                anchors.left: netIcon.right
                anchors.leftMargin: Style.spacing.xs
                anchors.right: netSignal.left
                anchors.rightMargin: Style.spacing.xs
                anchors.verticalCenter: parent.verticalCenter
                text: wifiNet.modelData.ssid
                color: wifiNet.modelData.active ? Colors.menu.selectedText : Colors.menu.text
                elide: Text.ElideRight
              }
              Label {
                id: netSignal
                anchors.right: parent.right
                anchors.rightMargin: Style.spacing.sm
                anchors.verticalCenter: parent.verticalCenter
                text: netRow.connecting ? "connecting"
                  : (wifiNet.modelData.known && !wifiNet.modelData.active ? "saved :: " : "") + wifiNet.modelData.signal + "%"
                dim: true
                highlighted: netRow.highlighted
                caption: true
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
              visible: netRow.pendingConnect && !wifiNet.modelData.active && !!wifiNet.modelData.enterprise
              width: parent.width
              leftPadding: Style.spacing.sm
              bottomPadding: Style.spacing.xs

              TextField {
                id: idInput
                width: parent.width - parent.leftPadding
                verticalPadding: Style.spacing.xs
                font.pixelSize: Style.font.caption
                placeholderText: "user@university.edu"
                onActiveFocusChanged: root.passwordFocused = activeFocus
                Component.onDestruction: if (activeFocus) root.passwordFocused = false
                onAccepted: pwInput.forceActiveFocus()
              }
            }

            Row {
              visible: netRow.pendingConnect && !wifiNet.modelData.active
              width: parent.width
              spacing: Style.spacing.xs
              leftPadding: Style.spacing.sm

              TextField {
                id: pwInput
                width: parent.width - parent.leftPadding - connectButton.width - parent.spacing
                verticalPadding: Style.spacing.xs
                font.pixelSize: Style.font.caption
                password: true
                placeholderText: "password"
                onActiveFocusChanged: root.passwordFocused = activeFocus
                Component.onDestruction: if (activeFocus) root.passwordFocused = false
                onAccepted: netRow.submit()
              }
              Button {
                id: connectButton
                anchors.verticalCenter: parent.verticalCenter
                variant: "action"
                focusable: true
                text: "Connect"
                onClicked: netRow.submit()
              }
            }
          }
        }

        PanelRow {
          visible: root.wifiShown.length < root.wifiNetworks.length
          width: content.width
          label: "All networks"
          trailing: "+" + (root.wifiNetworks.length - root.wifiShown.length)
          onActivated: root.wifiShowAll = true
        }

        Label {
          visible: root.wifiNetworks.length === 0 || wifiScanProc.running
          text: wifiScanProc.running ? "> SCANNING" : "> NOTHING HERE"
          dim: true
          caption: true
        }

        Label {
          visible: root.connectError !== ""
          width: content.width
          wrapMode: Text.Wrap
          text: root.connectError
          color: Colors.urgentText
          caption: true
        }
      }

      PanelSeparator {}
      PanelSectionHeader { text: "FIREWALL" }
      ButtonGroup {
        width: content.width
        fill: true
        spacing: Style.spacing.xs
        options: root.firewallModes
        value: root.firewallState
        opacity: root.busyOpacity("firewall")
        onChanged: function(state) { if (state !== root.firewallState) root.runToggle("firewall", "set", state) }
      }
      // trusting lifts the lockdown on this link: the gateway joins networkmanager's trusted_gateways (home stays home)
      ToggleRow {
        visible: root.toggleAvailable("trust-network")
        label: root.toggleLabel("trust-network", "Trusted network")
        on: root.toggleOn("trust-network")
        opacity: root.busyOpacity("trust-network")
        onActivated: root.runToggle("trust-network")
      }
      // offered while NM reports a portal or one is open: tor and strict dot keep its login page out of reach
      ToggleRow {
        visible: root.toggleAvailable("portal") && (root.connectivity === "portal" || root.portalOpen)
        label: root.toggleLabel("portal", "Captive portal")
        on: root.portalOpen
        opacity: root.busyOpacity("portal")
        onActivated: root.runToggle("portal")
      }

      PanelSeparator {}
      PanelSectionHeader { text: "ROUTE" }
      // the homelab chip sits beside the routes, toggled on its own: wg0 is a full tunnel (AllowedIPs 0.0.0.0/0) through
      // the router, which reaches the lab, the house lan and the internet, so while it is up the internet goes out home
      Row {
        width: content.width
        spacing: Style.spacing.xs

        ButtonGroup {
          width: parent.width - (homelabChip.visible ? homelabChip.width + parent.spacing : 0)
          fill: true
          spacing: Style.spacing.xs
          options: root.routeModes
          value: root.route
          opacity: root.busyOpacity("route")
          onChanged: function(state) { if (state !== root.route) root.runToggle("route", "set", state) }
        }

        RadioChip {
          id: homelabChip
          visible: root.toggleAvailable("vpn")
          text: "+ HOMELAB"
          toggle: "vpn"
        }
      }
      // the SOCKS pool listens on lo, beside any route
      ToggleRow {
        label: "Anonymous SOCKS"
        on: root.toggleOn("anonymous-socks")
        opacity: root.busyOpacity("anonymous-socks")
        onActivated: root.runToggle("anonymous-socks")
      }

      PanelSeparator {}
      PanelSectionHeader { text: "RADIOS" }
      // one chip per radio, lit while it is on: four toggle rows took a row each
      Flow {
        width: content.width
        spacing: Style.spacing.xs

        RadioChip { text: "WI-FI"; toggle: "wifi"; selected: root.wifiOn }
        RadioChip { text: "ETHERNET"; toggle: "ethernet" }
        RadioChip { visible: root.toggleAvailable("mobile"); text: "MOBILE"; toggle: "mobile" }
        RadioChip { text: "BLUETOOTH"; toggle: "bluetooth" }
      }

      PanelSeparator {}
      PanelSectionHeader { text: "TOOLS" }
      ToggleRow {
        label: "Internet speed test"
        glyph: "\u{f04c5}"
        onActivated: root.summon("panel.speedtest", "{}")
      }

      ToggleRow {
        visible: root.detailsConnected && !root.onEthernet
        label: "Share Wi-Fi (QR)"
        glyph: "\u{f0432}"
        onActivated: root.summon("panel.wifiqr", JSON.stringify({ iface: root.detailsDevice }))
      }
    }
  }
}

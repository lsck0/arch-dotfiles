pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Bluetooth
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

  // the network toggles' status records (scripts/toggles/status.nu), by name; a toggle without one is unknown ("")
  // and claims nothing. A failed refresh keeps the last records, marked stale on the bar by their age.
  property var toggles: ({})
  property real togglesUpdatedMs: 0
  property string togglesError: ""
  function toggleState(name) { return toggles[name] ? toggles[name].state : "" }
  function toggleOn(name) { return toggleState(name) === "on" }
  function toggleError(name) { return toggleState(name) === "error" }
  // a section's header, marked when one of its toggles cannot read its state
  function sectionError(names) { return names.some(name => toggleError(name)) }
  function toggleAvailable(name) { return !!toggles[name] && toggles[name].available }
  function toggleLabel(name, fallback) { return toggles[name] && toggles[name].label ? toggles[name].label : fallback }
  readonly property var toggleNames: ["route", "vpn", "anonymous-socks", "bluetooth", "wifi", "ethernet", "mobile", "firewall",
    "trust-network", "portal"]

  readonly property string homeVpnState: toggleState("vpn")
  readonly property string route: toggleState("route")
  readonly property bool vpnOn: homeVpnState === "on" || route === "proton"
  // traffic leaves through a tunnel: the bar glyph takes the accent
  readonly property bool tunnelled: vpnOn || route === "tor"
  readonly property bool wifiOn: toggleOn("wifi")
  readonly property bool offlineModeOn: route === "offline"
  readonly property string firewallState: toggleState("firewall")
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

  // bluez through Quickshell.Bluetooth; the section shows only while the default adapter is powered
  readonly property BluetoothAdapter btAdapter: Bluetooth.defaultAdapter // qmllint disable unresolved-type
  readonly property bool btOn: !!btAdapter && btAdapter.enabled
  // connected, then paired, then what a scan found; a discovered device without a name is noise
  readonly property var btDevices: {
    if (!btOn) return []
    var list = btAdapter.devices.values.filter(d => d.connected || d.paired || d.deviceName !== "") // qmllint disable missing-property
    function rank(d) { return d.connected ? 0 : d.paired ? 1 : 2 }
    return list.sort((a, b) => rank(a) - rank(b) || a.name.localeCompare(b.name))
  }
  // shares the panel with the Wi-Fi list: the first few, the rest behind "All devices"
  readonly property int btShownCountMax: 4
  property bool btShowAll: false
  readonly property var btShown: btShowAll ? btDevices : btDevices.slice(0, btShownCountMax)

  // a scan this panel started runs while it is open, at most btScanMaxMs; one another client started is only shown
  readonly property int btScanMaxMs: 60 * 1000
  property BluetoothAdapter btScanAdapter: null // qmllint disable unresolved-type
  readonly property bool btScanning: !!btAdapter && btAdapter.discovering
  function btScan(on) {
    if (on && btOn && !btScanAdapter) {
      btScanAdapter = btAdapter
      btAdapter.discovering = true
      btScanStop.restart()
    } else if (!on && btScanAdapter) {
      btScanStop.stop()
      btScanAdapter.discovering = false
      btScanAdapter = null
    }
  }

  // pair, then trust and connect: the intent lives here, keyed by device, so a re-sorted list keeps it
  property var btPending: []
  // address -> true: the last pair asked for here ended without a bond (rejected, timed out, wrong code)
  property var btFailed: ({})
  function btPair(device) {
    btFailed = Util.mapWithout(btFailed, device.address)
    if (btPending.indexOf(device) < 0) btPending = btPending.concat([device])
    device.pair()
  }
  function btPairDone(device, ok) {
    btPending = btPending.filter(d => d !== device)
    if (!ok) {
      btFailed = Util.mapSet(btFailed, device.address, true)
      return
    }
    device.trusted = true
    device.connect()
  }
  readonly property string btRequestText: {
    var r = BluetoothAgent.request
    if (!r) return ""
    switch (r.type) {
    case "confirm": return "Does " + r.name + " show " + r.passkey + "?"
    case "authorize": return "Allow " + r.name + " to pair?"
    case "service": return "Allow " + r.name + " to use service " + r.passkey + "?"
    case "pin": return "PIN for " + r.name
    case "passkey": return "Passkey for " + r.name
    case "display-pin": return "Type PIN " + r.passkey + " on " + r.name
    case "display-passkey": return "Type " + r.passkey + " on " + r.name + ", then Enter"
    default: return ""
    }
  }
  readonly property bool btRequestInput: !!BluetoothAgent.request
    && (BluetoothAgent.request.type === "pin" || BluetoothAgent.request.type === "passkey")

  function btIcon(icon) {
    if (icon.indexOf("headset") >= 0) return "\u{f02ce}"
    if (icon.indexOf("audio") >= 0) return "\u{f02cb}"
    if (icon.indexOf("mouse") >= 0) return "\u{f037d}"
    if (icon.indexOf("keyboard") >= 0) return "\u{f030c}"
    if (icon.indexOf("gaming") >= 0) return "\u{f0297}"
    if (icon.indexOf("phone") >= 0) return "\u{f011c}"
    if (icon.indexOf("computer") >= 0) return "\u{f0322}"
    return "\u{f00af}"
  }

  // network-details.nu counts KiB a second
  function speedText(kibPerSecond) { return Util.bytes(kibPerSecond * 1024) + "/s" }

  implicitWidth: trigger.implicitWidth + Style.bar.itemPaddingX * 2

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
    btShowAll = false
    btFailed = ({})
    if (now - lastRefreshMs >= refreshMinAgeMs || togglesError !== "") refreshAll()
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
    // a run at login can die before the session is up; without a retry the bar keeps "x ERR" until a network event
    retryDelaysMs: [2, 5, 10, 30, 60].map(function (s) { return s * 1000 })
    onParsed: function (data) {
      if (!Util.isList(data)) {
        root.togglesError = "bad json"
        togglesProc.retryStart()
        return
      }
      togglesProc.retryStop()
      var next = {}
      for (let i = 0; i < data.length; i++) if (data[i] && data[i].name) next[data[i].name] = data[i]
      root.toggles = next
      root.togglesError = ""
      root.togglesUpdatedMs = Date.now()
    }
    onFailed: root.togglesError = "bad json"
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

  EventWatcher {
    id: nmMonitor
    command: ["nmcli", "monitor"]
    onFired: root.refreshAll()
  }

  Connections {
    target: ToggleEvents
    function onChanged(script) {
      var name = script.replace(/^toggle-(.*)\.nu$/, "$1")
      if (root.toggleBusy(name)) root.busyToggles = Util.mapWithout(root.busyToggles, name)
      if (root.toggleNames.indexOf(name) >= 0) nmMonitor.queue()
    }
  }

  // Wi-Fi turned on with the panel open: scan now and once more when the radio is up (the first rescan can come too
  // early); nothing else refreshes the list while the panel stays open
  onWifiOnChanged: if (wifiOn && panel.visible) {
    refreshWifiList(true)
    wifiSettleScan.restart()
  }
  Timer {
    id: wifiSettleScan
    interval: 3000
    onTriggered: if (root.wifiOn && panel.visible) root.refreshWifiList(true)
  }

  Timer {
    id: btScanStop
    interval: root.btScanMaxMs
    onTriggered: root.btScan(false)
  }
  Connections {
    target: panel
    function onShownChanged() {
      if (!panel.shown) root.btScan(false)
      BluetoothAgent.viewers += panel.shown ? 1 : -1
    }
  }
  Component.onDestruction: {
    btScan(false)
    if (panel.shown) BluetoothAgent.viewers -= 1
  }
  Instantiator {
    model: root.btPending
    delegate: Connections {
      required property BluetoothDevice modelData
      target: modelData
      function onPairedChanged() { if (modelData.paired) root.btPairDone(modelData, true) }
      function onPairingChanged() { if (!modelData.pairing && !modelData.paired) root.btPairDone(modelData, false) }
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
    DataState {
      anchors.verticalCenter: parent.verticalCenter
      loading: togglesProc.running
      error: root.togglesError
      updatedMs: root.togglesUpdatedMs
    }
  }

  HoverPanel {
    id: panel
    anchorWidget: root
    onOpened: root.panelOpened()
    pinned: root.passwordFocused || !!BluetoothAgent.request
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

            ListRow {
              id: netRow
              property bool pendingConnect: false
              readonly property bool connecting: root.connectingSsid === wifiNet.modelData.ssid
              readonly property bool connectFailed: root.connectError !== "" && root.connectSsid === wifiNet.modelData.ssid
              width: parent.width
              selected: wifiNet.modelData.active
              glyph: wifiNet.modelData.active ? "*" : (wifiNet.modelData.secure ? "\u{f023}" : "\u{f1eb}")
              label: wifiNet.modelData.ssid
              trailing: connecting ? "connecting"
                : (wifiNet.modelData.known && !wifiNet.modelData.active ? "saved :: " : "") + wifiNet.modelData.signal + "%"
              activeFocusOnTab: !wifiNet.modelData.active
              onActivated: activate()

              function submit() {
                root.connectTo(wifiNet.modelData.ssid, pwInput.text, idInput.text)
                netRow.pendingConnect = false
              }

              function activate() {
                if (wifiNet.modelData.active) return
                // open, or saved: the profile's own secret; a wrong one fails into connectError, then this row's field shows
                if (!wifiNet.modelData.secure || (wifiNet.modelData.known && !netRow.pendingConnect && !netRow.connectFailed)) {
                  root.connectTo(wifiNet.modelData.ssid, "")
                  return
                }
                netRow.pendingConnect = !netRow.pendingConnect
                if (netRow.pendingConnect) Qt.callLater(wifiNet.modelData.enterprise ? idInput.forceActiveFocus : pwInput.forceActiveFocus)
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
          text: wifiScanProc.running ? "> SCANNING" : "> NO NETWORKS"
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

      PanelSeparator { visible: root.btOn }
      // with the adapter off there is nothing to list: the RADIOS section turns it on
      PanelSectionHeader { visible: root.btOn; text: "BLUETOOTH" }

      Column {
        visible: root.btOn
        width: content.width
        spacing: Style.spacing.xxs

        // the pairing agent's open question: a code to compare or type, a PIN to enter, a pairing or service to allow
        Column {
          visible: !!BluetoothAgent.request
          width: content.width
          spacing: Style.spacing.xs
          bottomPadding: Style.spacing.xs

          Label {
            // the device picks its name: plain text
            width: parent.width
            leftPadding: Style.spacing.sm
            wrapMode: Text.Wrap
            text: root.btRequestText
            color: Colors.accentText
          }
          Row {
            width: parent.width
            spacing: Style.spacing.xs
            leftPadding: Style.spacing.sm

            TextField {
              id: btCodeInput
              visible: root.btRequestInput
              width: parent.width - parent.leftPadding - btAccept.width - btReject.width - parent.spacing * 2
              verticalPadding: Style.spacing.xs
              font.pixelSize: Style.font.caption
              placeholderText: BluetoothAgent.request && BluetoothAgent.request.type === "passkey" ? "000000" : "PIN"
              inputMethodHints: BluetoothAgent.request && BluetoothAgent.request.type === "passkey" ? Qt.ImhDigitsOnly : Qt.ImhNone
              onActiveFocusChanged: root.passwordFocused = activeFocus
              Component.onDestruction: if (activeFocus) root.passwordFocused = false
              onAccepted: btAccept.clicked()
            }
            Button {
              id: btAccept
              visible: BluetoothAgent.needsAnswer
              anchors.verticalCenter: parent.verticalCenter
              variant: "action"
              focusable: true
              text: root.btRequestInput ? "Pair" : "Accept"
              onClicked: {
                BluetoothAgent.respond(true, btCodeInput.text)
                btCodeInput.text = ""
              }
            }
            Button {
              id: btReject
              anchors.verticalCenter: parent.verticalCenter
              variant: "action"
              focusable: true
              text: BluetoothAgent.needsAnswer ? "Reject" : "Dismiss"
              onClicked: {
                BluetoothAgent.respond(false)
                btCodeInput.text = ""
              }
            }
          }
        }

        Repeater {
          // diffed by device: a re-sort keeps rows, their focus and hover
          model: ScriptModel { values: root.btShown }
          delegate: ListRow {
            id: btRow
            required property BluetoothDevice modelData
            readonly property int deviceState: modelData.state // qmllint disable unresolved-type
            readonly property bool busy: modelData.pairing || deviceState === BluetoothDeviceState.Connecting
              || deviceState === BluetoothDeviceState.Disconnecting
            width: content.width
            opacity: busy ? Style.emphasis.dim : 1
            selected: modelData.connected
            failed: root.btFailed[modelData.address] === true
            controlHovered: btForget.hot
            glyph: root.btIcon(modelData.icon)
            label: modelData.name
            trailing: {
              var d = btRow.modelData
              if (d.pairing) return "pairing"
              if (btRow.deviceState === BluetoothDeviceState.Connecting) return "connecting"
              if (btRow.deviceState === BluetoothDeviceState.Disconnecting) return "disconnecting"
              if (btRow.failed) return "pairing failed"
              var battery = d.batteryAvailable ? " :: " + Math.round(d.battery * 100) + "%" : ""
              // a press disconnects: say so where the press lands
              if (d.connected) return (btRow.activeFocus || (btRow.hovered && !btForget.hot) ? "disconnect" : "connected") + battery
              return d.paired ? "saved" : "new"
            }
            Keys.onDeletePressed: btRow.forget()
            onActivated: {
              if (busy) return
              if (modelData.connected) modelData.disconnect()
              else if (modelData.paired) modelData.connect()
              else root.btPair(modelData)
            }
            onSecondaryActivated: forget()

            function forget() {
              if (modelData.paired) modelData.forget()
            }

            // its place stays reserved on a paired row, so the status does not jump under the pointer
            Button {
              id: btForget
              visible: btRow.modelData.paired
              opacity: btRow.hovered || btRow.activeFocus ? 1 : 0
              variant: "icon"
              iconText: "\u{f0156}"
              tooltipText: "Forget"
              onClicked: btRow.forget()
            }
          }
        }

        PanelRow {
          visible: root.btShown.length < root.btDevices.length
          width: content.width
          label: "All devices"
          trailing: "+" + (root.btDevices.length - root.btShown.length)
          onActivated: root.btShowAll = true
        }

        Label {
          visible: root.btDevices.length === 0
          text: root.btScanning ? "> SCANNING" : "> NO DEVICES"
          dim: true
          caption: true
        }

        ToggleRow {
          label: root.btScanning ? "Scanning for devices" : "Scan for devices"
          on: root.btScanning
          onActivated: root.btScan(!root.btScanAdapter)
        }
      }

      PanelSeparator {}
      PanelSectionHeader {
        readonly property bool failed: root.sectionError(["firewall", "trust-network", "portal"])
        text: "FIREWALL" + (failed ? " :: ERR" : "")
        foreground: failed ? Colors.urgentText : Colors.accentText
      }
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
      PanelSectionHeader {
        readonly property bool failed: root.sectionError(["route", "vpn", "anonymous-socks"])
        text: "ROUTE" + (failed ? " :: ERR" : "")
        foreground: failed ? Colors.urgentText : Colors.accentText
      }
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

      PanelSeparator { visible: radios.visibleChildren.length > 0 }
      PanelSectionHeader {
        readonly property bool failed: root.sectionError(["wifi", "ethernet", "mobile", "bluetooth"])
        visible: radios.visibleChildren.length > 0
        text: "RADIOS" + (failed ? " :: ERR" : "")
        foreground: failed ? Colors.urgentText : Colors.accentText
      }
      // one chip per radio, lit while it is on: four toggle rows took a row each; a radio the machine lacks has none
      Flow {
        id: radios
        width: content.width
        spacing: Style.spacing.xs

        RadioChip { visible: root.toggleAvailable("wifi"); text: "WI-FI"; toggle: "wifi"; selected: root.wifiOn }
        RadioChip { visible: root.toggleAvailable("ethernet"); text: "ETHERNET"; toggle: "ethernet" }
        RadioChip { visible: root.toggleAvailable("mobile"); text: "MOBILE"; toggle: "mobile" }
        RadioChip { visible: root.toggleAvailable("bluetooth"); text: "BLUETOOTH"; toggle: "bluetooth" }
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

import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui

// New widget, not from omarchy-shell.
BarWidget {
  id: root
  moduleName: "network"

  readonly property string toggleDir: Paths.toggles

  property string homeVpnState: "off"
  property string protonVpnState: "off"
  property string torState: "off"
  property bool btPowered: false
  property bool wifiOn: true
  property bool offlineModeOn: false

  property bool detailsConnected: false
  // NM's own verdict: full | limited | portal | none | unknown.
  property string connectivity: "unknown"
  readonly property bool reallyOnline: connectivity === "full"
  property string detailsDevice: ""
  property string detailsSsid: ""
  property string detailsIp4: ""
  property string detailsMac: ""
  property int detailsRxKbps: 0
  property int detailsTxKbps: 0

  // Rolling throughput history for the panel sparklines (newest last, capped).
  property var rxHist: []
  property var txHist: []
  function _push(arr, v) { var a = arr.slice(); a.push(v); if (a.length > 60) a.shift(); return a }

  property var wifiNetworks: []
  property string connectingSsid: ""
  property string connectError: ""

  // Format KB/s value: >= 1024 → X.Y MB/s, otherwise X KB/s
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
    btProc.running = true
    wifiProc.running = true
    rfkillProc.running = true
    if (!detailsProc.running) detailsProc.running = true
  }

  function refreshWifiList(rescan) {
    wifiScanProc.command = rescan
      ? [scriptDir + "/network-wifi-scan.sh", "rescan"]
      : [scriptDir + "/network-wifi-scan.sh"]
    if (!wifiScanProc.running) wifiScanProc.running = true
  }

  function connectTo(ssid, password) {
    root.connectingSsid = ssid
    root.connectError = ""
    connectProc.command = password
      ? [scriptDir + "/network-wifi-connect.sh", ssid, password]
      : [scriptDir + "/network-wifi-connect.sh", ssid]
    connectProc.running = true
  }

  readonly property string scriptDir: Paths.barWidgets

  // Every toggle is detached and takes real time — a VPN dial-up, an rfkill round trip, bluetoothctl powering a controller.
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

  function toggleHomeVpn() { Quickshell.execDetached([toggleDir + "/toggle-vpn.sh", "toggle"]); afterToggle() }
  function toggleProtonVpn() { Quickshell.execDetached([toggleDir + "/toggle-protonvpn.sh", "toggle"]); afterToggle() }
  function toggleTor() { Quickshell.execDetached([toggleDir + "/toggle-tor.sh", "toggle"]); afterToggle() }
  function toggleBluetooth() { Quickshell.execDetached([toggleDir + "/toggle-bluetooth.sh", "toggle"]); afterToggle() }
  function toggleWifi() { Quickshell.execDetached([toggleDir + "/toggle-wifi.sh", "toggle"]); afterToggle() }
  // Offline mode tears tunnels down first and takes several seconds, which is the case the repeated re-read above exists for.
  function toggleOfflineMode() { Quickshell.execDetached([toggleDir + "/toggle-offline.sh", "toggle"]); afterToggle() }

  Process {
    id: homeVpnProc
    command: [root.toggleDir + "/toggle-vpn.sh", "get"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.homeVpnState = String(text || "off").trim() }
  }
  Process {
    id: protonVpnProc
    command: [root.toggleDir + "/toggle-protonvpn.sh", "get"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.protonVpnState = String(text || "off").trim() }
  }
  Process {
    id: torProc
    command: [root.toggleDir + "/toggle-tor.sh", "get"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.torState = String(text || "off").trim() }
  }
  Process {
    id: btProc
    command: [root.toggleDir + "/toggle-bluetooth.sh", "get"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.btPowered = String(text || "").trim() === "on" }
  }
  Process {
    id: wifiProc
    command: [root.toggleDir + "/toggle-wifi.sh", "get"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.wifiOn = String(text || "").trim() === "on" }
  }
  Process {
    id: rfkillProc
    command: [root.toggleDir + "/toggle-offline.sh", "get"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.offlineModeOn = String(text || "").trim() === "on" }
  }
  Process {
    id: detailsProc
    command: [root.scriptDir + "/network-details.sh"]
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
          root.rxHist = root._push(root.rxHist, root.detailsRxKbps)
          root.txHist = root._push(root.txHist, root.detailsTxKbps)
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

  // Event-driven instead of polled.
  Process {
    id: nmMonitorProc
    running: true
    command: ["nmcli", "monitor"]
    stdout: SplitParser {
      splitMarker: "\n"
      onRead: nmDebounce.restart()
    }
    // nmcli monitor exits if NetworkManager itself restarts; the fallback Timer below is what brings the panel back in that window, and this restarts the monitor once NM is back.
    onExited: nmRestartTimer.restart()
  }

  // One NM change fans out into several monitor lines; coalesce them so a single reconnect doesn't fire refreshAll five times.
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

  // Fallback only.
  Timer {
    interval: 30000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refreshAll()
  }

  // SPEC: "showing connection(s) (ie do we have internet, if so lan/wifi?)".
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

  // Not a BarIconButton: that renders a single glyph and hard-sets labelVisible: false, so it cannot show speed text beside the icon.
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
      // Neon bloom only when a tunnel/radio path is live, so the glow reads as an active state.
      layer.enabled: Style.fx.glow > 0 && (root.homeVpnState === "on" || root.protonVpnState === "on" || root.torState === "on")
      layer.effect: MultiEffect {
        shadowEnabled: true
        shadowColor: Style.fx.glowColor
        shadowBlur: 1.0
        shadowVerticalOffset: 0
        shadowHorizontalOffset: 0
        blurMax: Style.fx.glowRadius
        autoPaddingEnabled: true
      }
    }
    // No throughput in the bar.
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
    // Load-bearing.
    acceptsKeyboard: true
    title: "NETWORK"
    implicitWidth: Style.panelWidth.normal + Style.shadowOffset
    implicitHeight: content.implicitHeight + padding * 2 + Style.shadowOffset

    // Neon HUD corner brackets around the dropdown.
    HudFrame {}

    Column {
      id: content
      width: parent.width
      spacing: Style.spacing.sm

      // Headroom so the terminal title strip never overlaps the first row.
      Item { width: 1; height: Style.spacing.xl }

      // This panel's rows were an in-file `Row_` component; they are the shared Ui/PanelRow now, along with the equivalent rows in the audio, display, system and media panels.
      component Row_: PanelRow {
        width: content.width
        stateMarker: glyph === ""
      }

      PanelSectionHeader {
        visible: root.detailsConnected
        text: "> DETAILS"
      }
      Column {
        width: content.width
        spacing: Style.spacing.xs
        visible: root.detailsConnected
        // Shown even when a device is "connected", because that is exactly when it is misleading: a link with an IP but no route out, or a captive portal, both look connected at the device level.
        Row {
          width: parent.width
          Text { width: parent.width * 0.35; text: "Status"; color: Color.menu.text; opacity: 0.5; font.pixelSize: Style.font.caption; font.family: Style.font.family }
          Text {
            width: parent.width * 0.65
            horizontalAlignment: Text.AlignRight
            text: root.connectivityLabel + (root.onEthernet ? "  ·  LAN" : "  ·  Wi-Fi")
            color: root.reallyOnline ? Color.menu.text : Color.menu.selectedText
            opacity: root.reallyOnline ? 1.0 : 0.9
            font.pixelSize: Style.font.caption
            font.family: Style.font.family
          }
        }
        Row {
          width: parent.width
          Text { width: parent.width * 0.35; text: "Device"; color: Color.menu.text; opacity: 0.5; font.pixelSize: Style.font.caption; font.family: Style.font.family }
          Text { width: parent.width * 0.65; horizontalAlignment: Text.AlignRight; text: root.detailsDevice + (root.detailsSsid ? " (" + root.detailsSsid + ")" : ""); color: Color.menu.text; font.pixelSize: Style.font.caption; font.family: Style.font.family; elide: Text.ElideLeft }
        }
        Row {
          width: parent.width
          Text { width: parent.width * 0.35; text: "IP"; color: Color.menu.text; opacity: 0.5; font.pixelSize: Style.font.caption; font.family: Style.font.family }
          Text { width: parent.width * 0.65; horizontalAlignment: Text.AlignRight; text: root.detailsIp4 || "—"; color: Color.menu.text; font.pixelSize: Style.font.caption; font.family: Style.font.family }
        }
        Row {
          width: parent.width
          Text { width: parent.width * 0.35; text: "MAC"; color: Color.menu.text; opacity: 0.5; font.pixelSize: Style.font.caption; font.family: Style.font.family }
          Text { width: parent.width * 0.65; horizontalAlignment: Text.AlignRight; text: root.detailsMac || "—"; color: Color.menu.text; font.pixelSize: Style.font.caption; font.family: Style.font.family }
        }
        Row {
          width: parent.width
          Text { width: parent.width * 0.35; text: "Speed"; color: Color.menu.text; opacity: 0.5; font.pixelSize: Style.font.caption; font.family: Style.font.family }
          Text { width: parent.width * 0.65; horizontalAlignment: Text.AlignRight; text: "↓" + root.fmtSpeed(root.detailsRxKbps) + "  ↑" + root.fmtSpeed(root.detailsTxKbps); color: Color.menu.text; font.pixelSize: Style.font.caption; font.family: Style.font.family }
        }
      }
      PanelSeparator {
        visible: root.detailsConnected
      }
      PanelSectionHeader { visible: root.detailsConnected; text: "> THROUGHPUT" }

      // Big glowing download hero plus rolling down/up history sparklines.
      Column {
        visible: root.detailsConnected
        width: content.width
        spacing: Style.spacing.xs

        Row {
          spacing: Style.spacing.xxs
          Text {
            id: dlHero
            anchors.bottom: parent.bottom
            text: root.fmtSpeed(root.detailsRxKbps)
            color: Color.accent
            font.family: Style.font.family
            font.pixelSize: Math.round(Style.font.display * 1.1)
            font.bold: true
            font.letterSpacing: Style.displayTracking
            layer.enabled: Style.fx.glow > 0
            layer.effect: MultiEffect {
              shadowEnabled: true
              shadowColor: Style.fx.glowColor
              shadowBlur: 1.0
              shadowVerticalOffset: 0
              shadowHorizontalOffset: 0
              blurMax: Style.fx.glowRadius
              autoPaddingEnabled: true
            }
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
      PanelSectionHeader { text: "> WI-FI NETWORKS" }

      Column {
        width: content.width
        spacing: Style.spacing.xxs

        Repeater {
          model: root.wifiNetworks
          delegate: Column {
            id: netDelegate
            required property var modelData
            required property int index
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
                // The connected network's live dot gets the neon halo.
                layer.enabled: Style.fx.glow > 0 && modelData.active
                layer.effect: MultiEffect {
                  shadowEnabled: true
                  shadowColor: Style.fx.glowColor
                  shadowBlur: 1.0
                  shadowVerticalOffset: 0
                  shadowHorizontalOffset: 0
                  blurMax: Style.fx.glowRadius
                  autoPaddingEnabled: true
                }
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
              // Right-aligned like PanelRow's trailing value.
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
              id: passwordField
              visible: netRow.pendingConnect && !modelData.active
              width: parent.width
              spacing: Style.spacing.xs
              leftPadding: Style.spacing.lg

              Rectangle {
                width: parent.width - 70 - parent.spacing
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
                width: 70
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
          text: "No networks found — scanning..."
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
      PanelSectionHeader { text: "> TUNNELS" }
      Row_ { label: "ProtonVPN"; on: root.protonVpnState === "on"; onActivated: root.toggleProtonVpn() }
      Row_ { label: "Homelab VPN"; on: root.homeVpnState === "on"; onActivated: root.toggleHomeVpn() }
      Row_ { label: "Tor Network"; on: root.torState === "on"; onActivated: root.toggleTor() }

      PanelSeparator {}
      PanelSectionHeader { text: "> RADIOS" }
      Row_ { label: "Wi-Fi"; on: root.wifiOn; onActivated: root.toggleWifi() }
      Row_ { label: "Bluetooth"; on: root.btPowered; onActivated: root.toggleBluetooth() }
      Row_ { label: "Offline mode"; on: root.offlineModeOn; onActivated: root.toggleOfflineMode() }

      PanelSeparator {}
      PanelSectionHeader { text: "> TOOLS" }
      // The speed test plugin was built, enabled and keepLoaded — and completely unreachable: nothing in the shell, no keybind and no menu entry ever summoned `panel.speedtest`, so the only way to run it was to type the ipc call by hand.
      Row_ {
        label: "Internet speed test"
        glyph: "\u{f04c5}"
        onActivated: {
          if (root.bar) root.bar.closePanel(root.moduleName)
          Quickshell.execDetached(Paths.ipcCall("shell", "summon", "panel.speedtest", "{}"))
        }
      }

      // panel.wifiqr was the SECOND plugin in exactly the same state: a finished Wi-Fi share card (QR matrix rendered as native rectangles, plus a password reveal, with scripts/network-qr.sh and scripts/network-password.sh behind it), enabled, keepLoaded, and summoned by nothing.
      Row_ {
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

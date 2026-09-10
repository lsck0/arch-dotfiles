import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui

// New widget, not from omarchy-shell. Every state change goes through
// toggles/*.sh — same backend as the toggles bar widget and the tmux menu,
// per the "toggles/*.sh is the only place this logic lives" rule. This
// widget only *reads*; it never runs rfkill/nmcli/bluetoothctl to write.
//
// Bluetooth, wifi and offline mode used to be the exception here, poking
// those tools inline. That is what hid the offline-mode bug: a bare
// `rfkill block all` only covers radios, so ethernet stayed up while the
// panel said "offline". See toggles/toggle-offline.sh for the fix.
//
// Portmaster: it runs a local web UI on 127.0.0.1:817 with no documented
// public REST API (probed directly — only its own UI paths respond), so
// "stats" here is limited to whether portmaster-core is actually running;
// the button opens its real web UI rather than faking a stats readout.
BarWidget {
  id: root
  moduleName: "network"

  readonly property string quickshellConfigPath: Quickshell.env("HOME") + "/.config/quickshell"
  readonly property string toggleDir: Quickshell.env("HOME") + "/projects/arch-dotfiles/toggles"

  property string homeVpnState: "off"
  property string protonVpnState: "off"
  property string torState: "off"
  property bool btPowered: false
  property bool wifiOn: true
  property bool offlineModeOn: false
  property bool portmasterRunning: false

  property bool detailsConnected: false
  // NM's own verdict: full | limited | portal | none | unknown. Distinct
  // from detailsConnected, which only says a device has a link.
  property string connectivity: "unknown"
  readonly property bool reallyOnline: connectivity === "full"
  property string detailsDevice: ""
  property string detailsSsid: ""
  property string detailsIp4: ""
  property string detailsMac: ""
  property int detailsRxKbps: 0
  property int detailsTxKbps: 0

  property var wifiNetworks: []
  property string connectingSsid: ""
  property string connectError: ""

  // Format KB/s value: >= 1024 → X.Y MB/s, otherwise X KB/s
  function fmtSpeed(kbps) {
    if (kbps >= 1024)
      return (Math.round(kbps / 1024 * 10) / 10) + " MB/s"
    return kbps + " KB/s"
  }

  readonly property bool showSpeeds: detailsConnected && (detailsRxKbps > 0 || detailsTxKbps > 0)

  implicitWidth: trigger.implicitWidth + Style.spacing.controlPaddingX * 2
  implicitHeight: barSize

  function refreshAll() {
    homeVpnProc.running = true
    protonVpnProc.running = true
    torProc.running = true
    btProc.running = true
    wifiProc.running = true
    rfkillProc.running = true
    portmasterProc.running = true
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

  readonly property string scriptDir: Quickshell.env("HOME") + "/projects/arch-dotfiles/configs/quickshell/plugins/bar/widgets"

  function toggleHomeVpn() { Quickshell.execDetached([toggleDir + "/toggle-vpn.sh", "toggle"]); Qt.callLater(refreshAll) }
  function toggleProtonVpn() { Quickshell.execDetached([toggleDir + "/toggle-protonvpn.sh", "toggle"]); Qt.callLater(refreshAll) }
  function toggleTor() { Quickshell.execDetached([toggleDir + "/toggle-tor.sh", "toggle"]); Qt.callLater(refreshAll) }
  function toggleBluetooth() { Quickshell.execDetached([toggleDir + "/toggle-bluetooth.sh", "toggle"]); Qt.callLater(refreshAll) }
  function toggleWifi() { Quickshell.execDetached([toggleDir + "/toggle-wifi.sh", "toggle"]); Qt.callLater(refreshAll) }
  // Offline mode tears tunnels down first and takes several seconds; the
  // nmcli monitor below catches the result, so no extra polling here.
  function toggleOfflineMode() { Quickshell.execDetached([toggleDir + "/toggle-offline.sh", "toggle"]); Qt.callLater(refreshAll) }

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
    id: portmasterProc
    command: ["bash", "-lc", "pgrep -x portmaster-core >/dev/null && echo on || echo off"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.portmasterRunning = String(text || "").trim() === "on" }
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

  // Event-driven instead of polled. `nmcli monitor` is a long-lived process
  // that prints a line whenever NM's state changes (device up/down,
  // connectivity re-check, radio toggled), so the panel reacts immediately
  // to a change made anywhere -- a keybind, menu.sh, or unplugging a cable --
  // rather than up to 10s later.
  Process {
    id: nmMonitorProc
    running: true
    command: ["nmcli", "monitor"]
    stdout: SplitParser {
      splitMarker: "\n"
      onRead: nmDebounce.restart()
    }
    // nmcli monitor exits if NetworkManager itself restarts; the fallback
    // Timer below is what brings the panel back in that window, and this
    // restarts the monitor once NM is back.
    onExited: nmRestartTimer.restart()
  }

  // One NM change fans out into several monitor lines; coalesce them so a
  // single reconnect doesn't fire refreshAll five times.
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

  // Fallback only. The monitor above carries normal updates; this catches
  // what NM does not report -- bluetooth power state, and any window where
  // the monitor process is down. Was a flat 10s poll of everything.
  Timer {
    interval: 30000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refreshAll()
  }

  // SPEC: "showing connection(s) (ie do we have internet, if so lan/wifi?)".
  // All six codepoints below are cmap-verified against 0xProto Nerd Font --
  // note md-lan_connect is U+F0318, NOT U+F0AA8 (that one exists but is
  // md-credit_card_refund_outline) and there is no nf-fa-network_wired here.
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

  // Not a BarIconButton: that renders a single glyph and hard-sets
  // labelVisible: false, so it cannot show speed text beside the icon.
  // Same Rectangle+Row+MouseArea idiom as Weather.qml / Media.qml.
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
    }
    Text {
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      visible: root.showSpeeds
      text: "↓" + root.fmtSpeed(root.detailsRxKbps) + " ↑" + root.fmtSpeed(root.detailsTxKbps)
      color: root.bar ? root.bar.barForeground : Color.foreground
      font.family: root.bar ? root.bar.fontFamily : Style.font.family
      font.pixelSize: Style.font.bodySmall
      opacity: 0.7
    }
  }

  MouseArea {
    id: hoverArea
    anchors.fill: parent
    hoverEnabled: true
    onEntered: { root.bar.hoverOpen(root.moduleName); root.refreshAll(); root.refreshWifiList(false) }
    onExited: root.bar.hoverTriggerExit(root.moduleName)
  }

  HoverPanel {
    id: panel
    bar: root.bar
    moduleName: root.moduleName
    anchorWidget: root
    implicitWidth: Style.space(340) + Style.shadowOffset
    implicitHeight: content.implicitHeight + padding * 2 + Style.shadowOffset

    Column {
      id: content
      width: parent.width
      spacing: Style.spacing.sm

      component Row_: Rectangle {
        property string label: ""
        property bool on: false
        // An action row runs something instead of representing on/off state,
        // so it takes an icon rather than the ●/○ state marker. Codepoint
        // verified against 0xProto's cmap with fontTools (f04c5 is
        // md-speedometer) — the repo has been bitten before by codepoints
        // that were present but drew a different glyph.
        property string glyph: ""
        signal activated()
        width: content.width
        height: Style.space(32)
        radius: Style.cornerRadius
        color: on ? Color.menu.selectedBackground : "transparent"
        Row {
          anchors.left: parent.left
          anchors.leftMargin: Style.spacing.md
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.spacing.sm
          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: parent.parent.glyph !== "" ? parent.parent.glyph : (parent.parent.on ? "●" : "○")
            color: parent.parent.on ? Color.menu.selectedText : Color.menu.text
            font.pixelSize: parent.parent.glyph !== "" ? Style.font.icon : Style.font.body
            font.family: parent.parent.glyph !== "" ? Style.font.iconFamily : Style.font.family
          }
          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: parent.parent.label
            color: parent.parent.on ? Color.menu.selectedText : Color.menu.text
            font.pixelSize: Style.font.body
            font.family: Style.font.family
          }
        }
        MouseArea {
          anchors.fill: parent
          cursorShape: Qt.PointingHandCursor
          onClicked: parent.activated()
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
        // Shown even when a device is "connected", because that is exactly
        // when it is misleading: a link with an IP but no route out, or a
        // captive portal, both look connected at the device level.
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
      PanelSectionHeader { text: "WI-FI NETWORKS" }

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
              height: Style.space(28)
              radius: Style.cornerRadius
              color: modelData.active ? Color.menu.selectedBackground : (netMouse.containsMouse ? Style.hoverFill : "transparent")

              Row {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: Style.spacing.md
                anchors.rightMargin: Style.spacing.md
                spacing: Style.spacing.sm

                Text {
                  text: modelData.active ? "●" : (modelData.secure ? "\u{f023}" : "\u{f1eb}")
                  color: modelData.active ? Color.menu.selectedText : Color.menu.text
                  font.pixelSize: Style.font.caption
                  font.family: Style.font.iconFamily
                }
                Text {
                  width: parent.width - 90
                  text: modelData.ssid
                  color: modelData.active ? Color.menu.selectedText : Color.menu.text
                  font.pixelSize: Style.font.body
                  font.family: Style.font.family
                  elide: Text.ElideRight
                }
                Text {
                  text: modelData.signal + "%"
                  color: Color.menu.text
                  opacity: 0.5
                  font.pixelSize: Style.font.caption
                  font.family: Style.font.family
                }
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
                height: Style.space(26)
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
                height: Style.space(26)
                radius: Style.cornerRadius
                color: Util.alpha(Color.accent, 0.15)
                Text {
                  anchors.centerIn: parent
                  text: root.connectingSsid === modelData.ssid ? "…" : "Connect"
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
          text: "No networks found — scanning…"
          color: Color.menu.text
          opacity: 0.4
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
      Row_ { label: "ProtonVPN"; on: root.protonVpnState === "on"; onActivated: root.toggleProtonVpn() }
      Row_ { label: "Homelab VPN"; on: root.homeVpnState === "on"; onActivated: root.toggleHomeVpn() }
      Row_ { label: "Tor Network"; on: root.torState === "on"; onActivated: root.toggleTor() }

      PanelSeparator {}
      PanelSectionHeader { text: "RADIOS" }
      Row_ { label: "Wi-Fi"; on: root.wifiOn; onActivated: root.toggleWifi() }
      Row_ { label: "Bluetooth"; on: root.btPowered; onActivated: root.toggleBluetooth() }
      Row_ { label: "Offline mode"; on: root.offlineModeOn; onActivated: root.toggleOfflineMode() }

      PanelSeparator {}
      PanelSectionHeader { text: "PORTMASTER" }
      Text {
        text: root.portmasterRunning ? "● running" : "○ not running"
        color: Color.menu.text
        opacity: root.portmasterRunning ? 1 : 0.5
        font.pixelSize: Style.font.body
        font.family: Style.font.family
      }

      PanelSeparator {}
      PanelSectionHeader { text: "TOOLS" }
      // The speed test plugin was built, enabled and keepLoaded — and
      // completely unreachable: nothing in the shell, no keybind and no menu
      // entry ever summoned `panel.speedtest`, so the only way to run it was
      // to type the ipc call by hand. This is the button it never had, in the
      // panel it obviously belongs to.
      Row_ {
        label: "Internet speed test"
        glyph: "\u{f04c5}"
        onActivated: {
          if (root.bar) root.bar.closePanel(root.moduleName)
          Quickshell.execDetached(["quickshell", "ipc", "-p", root.quickshellConfigPath,
                                   "call", "shell", "summon", "panel.speedtest", ""])
        }
      }
    }
  }
}

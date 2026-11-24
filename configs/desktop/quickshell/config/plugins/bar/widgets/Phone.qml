pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

BarWidget {
  id: root

  moduleName: "phone"
  barPriority: 30
  hoverPanel: true
  hoverFill: true
  hoverCursor: Qt.ArrowCursor

  readonly property string service: "org.kde.kdeconnect"
  readonly property string devicesPath: "/modules/kdeconnect/devices"
  readonly property int batteryLowPercent: 15
  // connectivity_report's strength scale: 0 to 4 bars
  readonly property int signalBarsMax: 4

  // phone-status.nu's record; the widget shows only while a paired device is reachable
  property bool available: false
  property string deviceId: ""
  property string deviceName: ""
  property int battery: -1
  property bool charging: false
  property int signalBars: -1
  property string network: ""
  property bool mounted: false
  property var actions: ({})
  property string statusError: ""

  readonly property bool hasBattery: battery >= 0
  readonly property bool batteryLow: hasBattery && !charging && battery <= batteryLowPercent

  visible: available
  implicitWidth: trigger.implicitWidth + Style.bar.itemPaddingX * 2

  function can(action) { return !!actions[action] }

  function cli(flag) {
    Quickshell.execDetached(["kdeconnect-cli", "--device", deviceId, flag])
  }

  // phone.nu (desktop/kdeconnect), linked into ~/.local/bin as `phone`, reports its own result
  function phone(verb, targets) {
    Quickshell.execDetached([Paths.bin("phone"), verb, "--notify"].concat(targets || []))
  }

  // the daemon mounts the phone over sftp and opens the mount in the file manager
  function browse() {
    Quickshell.execDetached(["busctl", "--user", "--auto-start=no", "call", service, devicesPath + "/" + deviceId + "/sftp",
      service + ".device.sftp", "startBrowsing"])
    closePanel()
  }

  function filePick() {
    if (pickProc.running) return
    closePanel()
    pickProc.command = ["zenity", "--file-selection", "--multiple", "--separator=\n", "--title=Send to " + deviceName,
      "--filename=" + Paths.home + "/"]
    pickProc.running = true
  }

  JsonProcess {
    id: statusProc
    command: [Paths.barWidget("phone-status.nu")]
    onParsed: function (d) {
      root.statusError = ""
      root.available = !!d.available
      root.deviceId = d.id || ""
      root.deviceName = d.name || ""
      root.battery = d.battery === null || d.battery === undefined ? -1 : d.battery
      root.charging = !!d.charging
      root.signalBars = d.signal === null || d.signal === undefined ? -1 : d.signal
      root.network = d.network || ""
      root.mounted = !!d.mounted
      root.actions = d.actions || {}
    }
    onFailed: function (error) { root.statusError = error }
  }
  Component.onCompleted: statusProc.run()

  // every signal the daemon sends (devices, battery, reachability, mounts, its name appearing or vanishing) reads the
  // state again, at most once per throttle interval
  EventWatcher {
    command: ["gdbus", "monitor", "--session", "--dest", root.service]
    debounceMs: 500
    throttle: true
    onFired: statusProc.run()
  }

  Process {
    id: pickProc
    stdout: StdioCollector {
      id: picked
      waitForEnd: true
    }
    onExited: function (exitCode) {
      if (exitCode !== 0) return
      var files = picked.text.split("\n").filter(function (f) { return f !== "" })
      if (files.length > 0) root.phone("share", files)
    }
  }

  Row {
    id: trigger
    anchors.centerIn: parent
    spacing: Style.spacing.xs

    Label {
      anchors.verticalCenter: parent.verticalCenter
      text: "\u{f011c}"
      color: root.batteryLow ? Colors.warnText : Colors.bar.text
      icon: true
      font.pixelSize: Style.font.icon
    }
    Label {
      anchors.verticalCenter: parent.verticalCenter
      visible: root.hasBattery
      text: root.battery + "%"
      color: root.batteryLow ? Colors.warnText : Colors.bar.text
      font.features: { "tnum": 1 }
    }
    Label {
      anchors.verticalCenter: parent.verticalCenter
      visible: root.charging
      text: "\u{f140b}"
      color: Colors.bar.text
      icon: true
      caption: true
    }
  }

  component ActionButton: Button {
    focusable: true
    variant: "action"
    width: (parent.width - Style.spacing.xs * 2) / 3
  }

  HoverPanel {
    id: panel
    anchorWidget: root
    onOpened: statusProc.run()
    title: "PHONE"
    implicitWidth: Style.panelWidth.narrow

    Column {
      id: content
      width: parent.width
      spacing: Style.spacing.xs

      // a device picks its own name: never markup
      StatRow { label: "Device"; value: root.deviceName }
      StatRow {
        visible: root.hasBattery
        label: "Battery"
        value: root.battery + "%"
        note: root.charging ? "charging" : ""
        valueColor: root.batteryLow ? Colors.warnText : Colors.menu.text
      }
      StatRow {
        visible: root.signalBars >= 0
        label: "Signal"
        value: (root.network ? root.network + " :: " : "") + root.signalBars + "/" + root.signalBarsMax
      }
      StatRow { visible: root.mounted; label: "Files"; value: "mounted" }
      StatRow { visible: root.statusError !== ""; label: "Status"; value: root.statusError; valueColor: Colors.urgentText }

      PanelSeparator {}

      Grid {
        width: content.width
        columns: 3
        spacing: Style.spacing.xs

        ActionButton { visible: root.can("ring"); text: "Ring"; onClicked: root.cli("--ring") }
        ActionButton { visible: root.can("ping"); text: "Ping"; onClicked: root.cli("--ping") }
        ActionButton { visible: root.can("browse"); text: "Browse"; onClicked: root.browse() }
        ActionButton { visible: root.can("clipboard"); text: "Clipboard"; onClicked: root.phone("clipboard") }
        ActionButton { visible: root.can("share"); text: "Send file"; onClicked: root.filePick() }
      }
    }
  }
}

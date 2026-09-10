import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import qs.Commons
import qs.Ui

// New widget, not from omarchy-shell. No voltage readout: this hardware has
// no exposed vcore sensor (checked with `sensors -j` before writing
// system-stats.sh) — showing a fake/zero value would be worse than not
// showing it. GPU is the integrated Intel iGPU (no discrete GPU on this
// hardware) — busy% and clock read from i915's own sysfs, no
// intel_gpu_top dependency (blocked by kernel.perf_event_paranoid=2 for a
// normal user anyway).
//
// Power-mode switching lives here too (not a separate widget): TLP-backed,
// via toggles/toggle-powermode.sh, which is also what the toggles menu and
// any keybind drive — this panel is just another consumer of the same
// script, not a second source of truth.
BarWidget {
  id: root
  moduleName: "system"

  property string cpuName: ""
  property int cpuCores: 0
  property string gpuName: ""
  property string gpuVendor: ""
  property int cpuPct: 0
  property int freqMhz: 0
  property int tempC: 0
  property real memUsedGb: 0
  property real memTotalGb: 0
  property string memType: ""
  property int memSpeedMts: 0
  property int memChannels: 0
  property int gpuPct: 0
  property int gpuFreqMhz: 0
  property var powerW: null
  property var vramUsedMb: null
  property var vramTotalMb: null

  readonly property var batteryDevice: UPower.displayDevice
  readonly property bool batteryPresent: batteryDevice && batteryDevice.isPresent === true
  readonly property bool onBattery: UPower.onBattery === true
  readonly property real batteryFraction: batteryPresent
    ? Math.max(0, Math.min(1, Number(batteryDevice.percentage) || 0)) : 0
  readonly property string batteryIcon: {
    if (!batteryPresent) return ""
    var level = Math.max(0, Math.min(9, Math.floor(batteryFraction * 10)))
    if (batteryDevice.state === UPowerDeviceState.FullyCharged) return "󰂅"
    return onBattery
      ? ["󰁺", "󰁻", "󰁼", "󰁽", "󰁾", "󰁿", "󰂀", "󰂁", "󰂂", "󰁹"][level]
      : ["󰢜", "󰂆", "󰂇", "󰂈", "󰢝", "󰂉", "󰢞", "󰂊", "󰂋", "󰂅"][level]
  }
  readonly property string batteryTime: {
    if (!batteryPresent) return ""
    var seconds = onBattery ? batteryDevice.timeToEmpty : batteryDevice.timeToFull
    var total = Math.max(0, Math.round(Number(seconds) || 0))
    var hours = Math.floor(total / 3600)
    var minutes = Math.floor((total % 3600) / 60)
    return hours > 0 ? hours + "h " + minutes + "m" : (minutes > 0 ? minutes + "m" : "")
  }

  // Empty string means "no override" — see toggles/toggle-powermode.sh's
  // get/auto contract (2026-09-06). Distinct from "balanced": that used to
  // double as the pre-refresh placeholder AND a real state, which made an
  // actual auto/no-override reading indistinguishable from "hasn't loaded
  // yet". Now empty is unambiguous and ButtonGroup simply shows no chip
  // selected until the process replies.
  property string powerMode: ""

  function refreshPowerMode() {
    if (!powerModeProc.running) powerModeProc.running = true
  }

  function setPowerMode(mode) {
    Quickshell.execDetached([root.powerModeScript, mode])
    Qt.callLater(root.refreshPowerMode)
  }

  readonly property string powerModeScript: Quickshell.env("HOME") + "/projects/arch-dotfiles/toggles/toggle-powermode.sh"

  Process {
    id: powerModeProc
    command: [root.powerModeScript, "get"]
    stdout: StdioCollector {
      id: powerModeOutput
      waitForEnd: true
    }
    onExited: {
      root.powerMode = (powerModeOutput.text || "").trim()
    }
  }

  Timer {
    interval: 5000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refreshPowerMode()
  }

  implicitWidth: label.implicitWidth + Style.spacing.controlPaddingX * 2
  implicitHeight: barSize

  Rectangle {
    anchors.fill: parent
    radius: Style.cornerRadius
    color: mouseArea.containsMouse ? Style.hoverFill : "transparent"
    Behavior on color { ColorAnimation { duration: 100 } }
  }

  // Long-lived, not respawned per sample (same shape as Cava.qml/cava and
  // Network.qml's `nmcli monitor` readers) — system-stats.sh streams one
  // JSON line per interval on its own, so this is just a SplitParser
  // reading whatever it prints, forever.
  Process {
    id: statsProc
    running: true
    command: [Quickshell.env("HOME") + "/projects/arch-dotfiles/configs/quickshell/plugins/bar/widgets/system-stats.sh"]
    stdout: SplitParser {
      splitMarker: "\n"
      onRead: function(line) {
        if (!line) return
        try {
          var s = JSON.parse(line)
          root.cpuName = s.cpuName || ""
          root.cpuCores = s.cpuCores || 0
          root.gpuName = s.gpuName || ""
          root.gpuVendor = s.gpuVendor || ""
          root.cpuPct = s.cpu || 0
          root.freqMhz = s.freqMhz || 0
          root.tempC = s.tempC || 0
          root.memUsedGb = s.memUsedGb || 0
          root.memTotalGb = s.memTotalGb || 0
          root.memType = s.memType || ""
          root.memSpeedMts = s.memSpeedMts || 0
          root.memChannels = s.memChannels || 0
          root.gpuPct = s.gpuPct || 0
          root.gpuFreqMhz = s.gpuFreqMhz || 0
          root.powerW = (s.powerW === undefined) ? null : s.powerW
          root.vramUsedMb = (s.vramUsedMb === undefined) ? null : s.vramUsedMb
          root.vramTotalMb = (s.vramTotalMb === undefined) ? null : s.vramTotalMb
        } catch (e) {}
      }
    }
  }

  Text {
    id: label
    anchors.centerIn: parent
    textFormat: Text.PlainText
    text: "󰻠 " + root.cpuPct + "% " + root.freqMhz + "MHz  󰍛 " + root.memUsedGb.toFixed(1) + "G  " + root.tempC + "°  \u{f061a} " + root.gpuPct + "%" + (root.batteryPresent ? "  " + root.batteryIcon + " " + Math.round(root.batteryFraction * 100) + "%" : "")
    color: root.bar ? root.bar.barForeground : Color.foreground
    font.family: root.bar ? root.bar.fontFamily : Style.font.family
    font.pixelSize: Style.font.body
  }

  MouseArea {
    id: mouseArea
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onEntered: { root.bar.hoverOpen(root.moduleName); root.refreshPowerMode() }
    onExited: root.bar.hoverTriggerExit(root.moduleName)
  }

  // A label/value pair row, reused across the CPU/GPU/RAM sections below
  // instead of hand-rolling the same two-Text-items layout five times.
  component Row_: Row {
    property string label: ""
    property string value: ""
    property bool dim: false
    width: parent.width
    Text {
      width: parent.width * 0.4
      text: parent.label
      color: Color.menu.text
      opacity: 0.6
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
    }
    Text {
      width: parent.width * 0.6
      horizontalAlignment: Text.AlignRight
      text: parent.value
      color: Color.menu.text
      opacity: parent.dim ? 0.4 : 1
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
    }
  }

  HoverPanel {
    id: panel
    bar: root.bar
    moduleName: root.moduleName
    anchorWidget: root
    // The power-mode chips sit in one horizontal row. Keep enough inner
    // width for all three labels plus ButtonGroup spacing; the old 280px card
    // let the final chip protrude beyond the BorderSurface.
    implicitWidth: Style.space(360) + Style.shadowOffset
    implicitHeight: content.implicitHeight + padding * 2 + Style.shadowOffset

    Column {
      id: content
      width: parent.width
      spacing: Style.spacing.md

      PanelSectionHeader { text: "CPU" }
      Text {
        width: parent.width
        visible: root.cpuName.length > 0
        text: root.cpuName + (root.cpuCores > 0 ? " (" + root.cpuCores + " threads)" : "")
        color: Color.menu.text
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        wrapMode: Text.WordWrap
      }
      Row_ { label: "Usage"; value: root.cpuPct + "%" }
      Row_ { label: "Clock"; value: root.freqMhz + " MHz" }
      Row_ { label: "Package temp"; value: root.tempC + "°C" }
      // No sensor → no row. A "Package power unavailable" line is noise.
      Row_ {
        visible: root.powerW !== null
        label: "Package power"
        value: root.powerW + " W"
      }

      PanelSeparator {}
      PanelSectionHeader { text: "MEMORY" }
      Row_ { label: "Used"; value: root.memUsedGb.toFixed(1) + " / " + root.memTotalGb.toFixed(1) + " GB" }
      // No SMBIOS reading (VM, permission denied, etc.) → row absent rather
      // than a placeholder.
      Row_ {
        visible: root.memType !== "" || root.memSpeedMts > 0
        label: "Type"
        value: [root.memType, root.memSpeedMts > 0 ? root.memSpeedMts + " MT/s" : ""].filter(function(v) { return v }).join(" · ")
      }
      Row_ {
        visible: root.memChannels > 0
        label: "Channels"
        value: root.memChannels + (root.memChannels > 1 ? "-channel" : " channel")
      }

      PanelSeparator {}
      PanelSectionHeader { text: "GPU" }
      Text {
        width: parent.width
        visible: root.gpuName.length > 0
        text: root.gpuName
        color: Color.menu.text
        font.family: Style.font.family; font.pixelSize: Style.font.caption
        wrapMode: Text.WordWrap
      }
      Row_ { label: "Usage"; value: root.gpuPct + "%" }
      Row_ { label: "Clock"; value: root.gpuFreqMhz + " MHz" }
      // VRAM is only shown where it's a real concept — an integrated GPU has
      // no separate video memory, so the row is simply absent rather than
      // showing "—" or a paragraph explaining why.
      Row_ {
        visible: root.gpuVendor !== "intel"
        label: "VRAM"
        value: root.vramTotalMb !== null
          ? Math.round(root.vramUsedMb) + " / " + Math.round(root.vramTotalMb) + " MB"
          : "unavailable"
        dim: root.vramTotalMb === null
      }

      PanelSeparator {}
      PanelSectionHeader { text: "BATTERY"; visible: root.batteryPresent }
      Row_ {
        visible: root.batteryPresent
        label: "Charge"
        value: Math.round(root.batteryFraction * 100) + "%" + (root.batteryTime ? " · " + root.batteryTime : "")
      }
      Row_ {
        visible: root.batteryPresent
        label: "State"
        value: root.onBattery ? "On battery" : "Charging"
      }

      PanelSeparator { visible: root.batteryPresent }
      PanelSectionHeader { text: "POWER MODE" }

      // No option is selected when powerMode is empty — that means no
      // runtime override is forced, so TLP is on its configured hardware
      // default (balanced/power-saver on battery machines, performance on
      // AC-only ones; see configs/tlp/tlp.conf vs. tlp.conf.ac-only). Any
      // override made here is deliberately session-only: it never survives
      // a reboot, matching the requested "overridable but non-persistent"
      // policy.
      ButtonGroup {
        width: parent.width
        spacing: Style.spacing.xs
        options: [
          { value: "power-saver", label: "Power saver" },
          { value: "balanced",    label: "Balanced" },
          { value: "performance", label: "Performance" }
        ]
        value: root.powerMode
        foreground: Color.menu.text
        background: "transparent"
        fontSize: Style.font.caption
        onChanged: function(value) { root.setPowerMode(value) }
      }
    }
  }
}

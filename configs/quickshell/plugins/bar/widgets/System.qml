import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import qs.Commons
import qs.Ui

// New widget, not from omarchy-shell.
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

  // Power mode lives entirely in Ui/PowerModeSelector — reader, writer, option list and chips.
  implicitWidth: label.implicitWidth + Style.bar.itemPaddingX * 2
  implicitHeight: barSize

  Rectangle {
    anchors.fill: parent
    radius: Style.cornerRadius
    color: mouseArea.containsMouse ? Style.hoverFill : "transparent"
    Behavior on color { ColorAnimation { duration: 100 } }
  }

  // Long-lived, not respawned per sample (same shape as Cava.qml/cava and Network.qml's `nmcli monitor` readers) — system-stats.sh streams one JSON line per interval on its own, so this is just a SplitParser reading whatever it prints, forever.
  Process {
    id: statsProc
    running: true
    command: [Paths.barWidget("system-stats.sh")]
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

  // ONE FIXED-WIDTH SLOT PER STAT, not one long string.
  component Stat: Row {
    property string glyph: ""
    property string value: ""
    // The widest string this stat can ever show.
    property string widest: ""
    spacing: Style.spacing.sm

    Text {
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      text: parent.glyph
      color: root.bar ? root.bar.barForeground : Color.foreground
      font.family: root.bar ? root.bar.iconFontFamily : Style.font.iconFamily
      font.pixelSize: Style.font.icon
      opacity: Style.emphasis.dim
    }
    Text {
      id: slotText
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      width: Math.ceil(sizer.implicitWidth)
      // AlignLeft, not AlignRight.
      horizontalAlignment: Text.AlignLeft
      text: parent.value
      color: root.bar ? root.bar.barForeground : Color.foreground
      font.family: root.bar ? root.bar.fontFamily : Style.font.family
      font.pixelSize: Style.font.body

      // Never drawn; exists only to report the width of the widest value.
      Text {
        id: sizer
        visible: false
        textFormat: Text.PlainText
        text: parent.parent.widest
        font.family: slotText.font.family
        font.pixelSize: slotText.font.pixelSize
      }
    }
  }

  Row {
    id: label
    anchors.centerIn: parent
    spacing: Style.spacing.lg

    // md-memory: despite the name it is the square CPU-package glyph.
    Stat { glyph: "\u{f035b}"; widest: "100%"; value: root.cpuPct + "%" }
    // fa-memory (DIMM stick).
    Stat {
      glyph: "\u{efc5}"
      widest: root.memTotalGb.toFixed(1) + "/" + root.memTotalGb.toFixed(0) + "G"
      value: root.memUsedGb.toFixed(1) + "/" + root.memTotalGb.toFixed(0) + "G"
    }
    // md-expansion_card (graphics card)
    Stat { glyph: "\u{f08ae}"; widest: "100%"; value: root.gpuPct + "%" }
    // VRAM only where it's a real concept — see the hover panel's own VRAM row below for why an iGPU has no row here.
    Stat {
      visible: root.gpuVendor !== "intel" && root.vramTotalMb !== null
      glyph: "\u{f061a}"
      widest: (root.vramTotalMb / 1024).toFixed(1) + "/" + (root.vramTotalMb / 1024).toFixed(1) + "G"
      value: (root.vramUsedMb / 1024).toFixed(1) + "/" + (root.vramTotalMb / 1024).toFixed(1) + "G"
    }
    // md-thermometer, unit spelled out: a bare "80" sitting between two percentages reads as a third percentage.
    Stat { glyph: "\u{f050f}"; widest: "100°C"; value: root.tempC + "°C" }
    Stat {
      visible: root.batteryPresent
      glyph: root.batteryIcon
      widest: "100%"
      value: Math.round(root.batteryFraction * 100) + "%"
    }
  }

  MouseArea {
    id: mouseArea
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    // PowerModeSelector reads on its own once the panel is visible (triggeredOnStart), so hover has nothing left to prime here.
    onEntered: root.bar.hoverOpen(root.moduleName)
    onExited: root.bar.hoverTriggerExit(root.moduleName)
  }

  // A label/value pair row, reused across the CPU/GPU/RAM sections below instead of hand-rolling the same two-Text-items layout five times.
  component Row_: Row {
    property string label: ""
    property string value: ""
    property bool dim: false
    width: parent.width
    Text {
      width: parent.width * 0.4
      text: parent.label
      color: Color.menu.text
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
    // The power-mode chips sit in one horizontal row.
    implicitWidth: Style.panelWidth.normal + Style.shadowOffset
    implicitHeight: content.implicitHeight + padding * 2 + Style.shadowOffset

    Column {
      id: content
      width: parent.width
      spacing: Style.spacing.md

      PanelSectionHeader { text: "System"; fontSize: Style.font.title }
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
      // No SMBIOS reading (VM, permission denied, etc.) → row absent rather than a placeholder.
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
      // VRAM is only shown where it's a real concept — an integrated GPU has no separate video memory, so the row is simply absent rather than showing "—" or a paragraph explaining why.
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

      // Any override made here is deliberately session-only: it never survives a reboot, matching the requested "overridable but non-persistent" policy.
      PowerModeSelector {
        width: parent.width
        active: panel.visible
      }

      PanelSeparator {}
      PanelSectionHeader { text: "TOOLS" }

      // panel.disk-speedtest was built, enabled, keepLoaded — and summoned by nothing, the same defect the internet speed test had before the Network panel grew a button for it.
      PanelRow {
        width: parent.width
        // md-harddisk U+F02CA, cmap-verified by name.
        glyph: "\u{f02ca}"
        label: "Disk speed test"
        onActivated: {
          if (root.bar) root.bar.closePanel(root.moduleName)
          Quickshell.execDetached(Paths.ipcCall("shell", "summon", "panel.disk-speedtest", "{}"))
        }
      }
    }
  }
}

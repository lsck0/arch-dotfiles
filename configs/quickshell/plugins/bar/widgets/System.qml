import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import qs.Commons
import qs.Ui
import "BatteryModel.js" as BatteryModel

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
  readonly property real memPct: memTotalGb > 0 ? memUsedGb / memTotalGb * 100 : 0
  property string memType: ""
  property int memSpeedMts: 0
  property int memChannels: 0
  property int gpuPct: 0
  property int gpuFreqMhz: 0
  property var powerW: null
  property var cpuPowerW: null
  property var gpuPowerW: null
  property real energyKwh: 0
  // assumed flat tariff, eur per kwh
  readonly property real pricePerKwh: 0.35
  property var vramUsedMb: null
  property var vramTotalMb: null

  property var cpuHist: []
  property var gpuHist: []
  property var memHist: []
  property var tempHist: []

  function critLoad(pct) {
    if (pct >= 92) return Color.semantic.live
    if (pct >= 80) return Color.semantic.recording
    if (pct >= 60) return Color.semantic.warn
    return Color.accent
  }
  function critTemp(t) {
    if (t >= 85) return Color.semantic.live
    if (t >= 75) return Color.semantic.recording
    if (t >= 60) return Color.semantic.warn
    return Color.accent
  }

  readonly property var batteryDevice: UPower.displayDevice
  readonly property bool batteryPresent: batteryDevice && batteryDevice.isPresent === true
  readonly property bool onBattery: UPower.onBattery === true
  readonly property var upowerStates: ({
    Charging: UPowerDeviceState.Charging,
    Discharging: UPowerDeviceState.Discharging,
    FullyCharged: UPowerDeviceState.FullyCharged,
    PendingCharge: UPowerDeviceState.PendingCharge
  })
  readonly property real batteryFraction: BatteryModel.batteryFraction(batteryDevice)
  readonly property string batteryIcon: BatteryModel.batteryIcon(batteryDevice, onBattery, upowerStates)
  readonly property string batteryTime: {
    if (!batteryPresent) return ""
    return BatteryModel.formatDuration(onBattery ? batteryDevice.timeToEmpty : batteryDevice.timeToFull)
  }

  implicitWidth: label.implicitWidth + Style.bar.itemPaddingX * 2
  implicitHeight: barSize

  Rectangle {
    anchors.fill: parent
    radius: Style.cornerRadius
    color: mouseArea.containsMouse ? Style.hoverFill : "transparent"
    Behavior on color { ColorAnimation { duration: 100 } }
  }

  // long-lived, the script streams on its own interval
  Process {
    running: true
    command: [Paths.barWidget("system-stats.sh"), root.onBattery ? "15" : "10"]
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
          root.cpuPowerW = (s.cpuPowerW === undefined) ? null : s.cpuPowerW
          root.gpuPowerW = (s.gpuPowerW === undefined) ? null : s.gpuPowerW
          root.energyKwh = s.energyKwh || 0
          root.vramUsedMb = (s.vramUsedMb === undefined) ? null : s.vramUsedMb
          root.vramTotalMb = (s.vramTotalMb === undefined) ? null : s.vramTotalMb
          root.cpuHist = Util.historyPush(root.cpuHist, root.cpuPct)
          root.gpuHist = Util.historyPush(root.gpuHist, root.gpuPct)
          root.memHist = Util.historyPush(root.memHist, root.memPct)
          root.tempHist = Util.historyPush(root.tempHist, root.tempC)
        } catch (e) {}
      }
    }
  }

  // fixed-width slot per stat so the bar does not jitter
  component Stat: Row {
    property string glyph: ""
    property string value: ""
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
      horizontalAlignment: Text.AlignLeft
      text: parent.value
      color: root.bar ? root.bar.barForeground : Color.foreground
      font.family: root.bar ? root.bar.fontFamily : Style.font.family
      font.pixelSize: Style.font.body
      font.letterSpacing: Style.displayTracking
      layer.enabled: Style.fx.glow > 0
      layer.effect: Glow {}

      // invisible, only measures the widest value
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

    // too wide for a vertical bar
    Sparkline {
      visible: !root.vertical
      anchors.verticalCenter: parent.verticalCenter
      width: Style.space(40)
      height: Style.space(14)
      values: root.cpuHist
      minValue: 0
      maxValue: 100
      color: Color.accent
    }

    // md-memory, the cpu package glyph
    Stat { glyph: "\u{f035b}"; widest: "100%"; value: root.cpuPct + "%" }
    // fa-memory
    Stat {
      glyph: "\u{efc5}"
      widest: root.memTotalGb.toFixed(1) + "/" + root.memTotalGb.toFixed(0) + "G"
      value: root.memUsedGb.toFixed(1) + "/" + root.memTotalGb.toFixed(0) + "G"
    }
    // md-expansion_card
    Stat { glyph: "\u{f08ae}"; widest: "100%"; value: root.gpuPct + "%" }
    // an igpu has no dedicated vram
    Stat {
      visible: root.gpuVendor !== "intel" && root.vramTotalMb !== null
      glyph: "\u{f061a}"
      widest: (root.vramTotalMb / 1024).toFixed(1) + "/" + (root.vramTotalMb / 1024).toFixed(1) + "G"
      value: (root.vramUsedMb / 1024).toFixed(1) + "/" + (root.vramTotalMb / 1024).toFixed(1) + "G"
    }
    // md-thermometer, unit spelled out so it does not read as a percentage
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
    onEntered: if (root.bar) root.bar.hoverOpen(root.moduleName)
    onExited: if (root.bar) root.bar.hoverTriggerExit(root.moduleName)
  }

  component SectionHead: Item {
    property string text: ""
    width: parent ? parent.width : 0
    implicitHeight: hdr.implicitHeight
    height: implicitHeight
    Text {
      id: lead
      anchors.left: parent.left
      anchors.verticalCenter: hdr.verticalCenter
      text: "#"
      color: Color.accent
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      opacity: Style.emphasis.dim
    }
    PanelSectionHeader {
      id: hdr
      anchors.left: lead.right
      anchors.leftMargin: Style.spacing.sm
      text: parent.text
    }
    Rectangle {
      anchors.left: hdr.right
      anchors.leftMargin: Style.spacing.sm
      anchors.right: parent.right
      anchors.verticalCenter: hdr.verticalCenter
      height: 1
      color: Util.alpha(Color.accent, 0.35)
    }
  }

  component HudStat: Column {
    property string label: ""
    property string value: ""
    property string note: ""
    property color tint: Color.foreground
    width: parent ? (parent.width - parent.spacing) / 2 : 0
    spacing: Style.spacing.hairline
    Text {
      text: parent.label
      color: Color.menu.text
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      font.capitalization: Font.AllUppercase
      font.letterSpacing: Style.headerTracking * 0.4
    }
    Text {
      text: parent.value
      color: parent.tint
      opacity: Style.emphasis.strong
      font.family: Style.font.family
      font.pixelSize: Style.font.title
      font.letterSpacing: Style.displayTracking
    }
    Text {
      visible: parent.note.length > 0
      text: parent.note
      color: Color.menu.text
      opacity: Style.emphasis.dim
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
    }
  }

  component FluxLabel: Item {
    property string text: ""
    property color tint: Color.accent
    width: parent ? parent.width : 0
    Text {
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      text: parent.text
      color: parent.tint
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      font.bold: true
      font.capitalization: Font.AllUppercase
      font.letterSpacing: Style.headerTracking * 0.4
    }
  }

  component Meter: Item {
    id: meterRoot
    property string label: ""
    property real fraction: 0
    property color fill: Color.accent
    property string value: ""
    property string secondary: ""
    readonly property real frac: Math.max(0, Math.min(1, fraction))
    width: parent ? parent.width : 0
    implicitHeight: Style.space(18)
    height: implicitHeight

    Text {
      id: meterLabel
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      width: Style.space(34)
      text: meterRoot.label
      color: Color.menu.text
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      font.capitalization: Font.AllUppercase
      font.letterSpacing: Style.headerTracking * 0.4
    }

    // fixed width so numerals align across rows
    Item {
      id: meterValue
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      width: Style.space(100)
      height: valPrimary.implicitHeight
      Text {
        id: valPrimary
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        text: meterRoot.value
        color: Color.foreground
        opacity: Style.emphasis.strong
        font.family: Style.font.family
        font.pixelSize: Style.font.body
        font.letterSpacing: Style.displayTracking
        layer.enabled: Style.fx.glow > 0
        layer.effect: Glow {}
      }
      Text {
        anchors.left: valPrimary.right
        anchors.leftMargin: Style.spacing.sm
        anchors.baseline: valPrimary.baseline
        visible: meterRoot.secondary.length > 0
        text: meterRoot.secondary
        color: Color.foreground
        opacity: Style.emphasis.faint
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        font.letterSpacing: Style.displayTracking
      }
    }

    Rectangle {
      anchors.left: meterLabel.right
      anchors.leftMargin: Style.spacing.sm
      anchors.right: meterValue.left
      anchors.rightMargin: Style.spacing.md
      anchors.verticalCenter: parent.verticalCenter
      height: Style.space(7)
      radius: Style.cornerRadius
      color: Util.alpha(Color.foreground, 0.12)
      Rectangle {
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: meterRoot.frac * parent.width
        radius: parent.radius
        color: meterRoot.fill
        Behavior on width { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
        Behavior on color { ColorAnimation { duration: 250 } }
        layer.enabled: Style.fx.glow > 0
        layer.effect: Glow { shadowColor: meterRoot.fill }
      }
    }
  }

  HoverPanel {
    id: panel
    bar: root.bar
    moduleName: root.moduleName
    anchorWidget: root
    implicitWidth: Style.panelWidth.normal
    implicitHeight: content.implicitHeight + padding * 2

    Column {
      id: content
      width: parent.width
      spacing: Style.spacing.md

      Item {
        width: parent.width
        implicitHeight: titleRow.implicitHeight
        height: implicitHeight
        Row {
          id: titleRow
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.spacing.xs
          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: ">"
            color: Color.accent
            opacity: Style.emphasis.dim
            font.family: Style.font.family
            font.pixelSize: Style.font.title
          }
          PanelSectionHeader { anchors.verticalCenter: parent.verticalCenter; text: "System"; fontSize: Style.font.title }
          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "_"
            color: Color.accent
            font.family: Style.font.family
            font.pixelSize: Style.font.title
            layer.enabled: Style.fx.glow > 0
            layer.effect: Glow {}
            SequentialAnimation on opacity {
              running: panel.visible
              loops: Animation.Infinite
              NumberAnimation { to: 0.15; duration: 520 }
              NumberAnimation { to: 1.0; duration: 520 }
            }
          }
        }
        Text {
          anchors.right: parent.right
          anchors.verticalCenter: titleRow.verticalCenter
          text: "# - x"
          color: Color.accent
          opacity: Style.emphasis.faint
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          font.letterSpacing: Style.headerTracking * 0.5
        }
      }
      PanelSeparator {}

      Column {
        width: parent.width
        spacing: Style.spacing.xs
        Meter {
          label: "CPU"
          fraction: root.cpuPct / 100
          fill: root.critLoad(root.cpuPct)
          value: root.cpuPct + "%"
          secondary: (root.freqMhz / 1000).toFixed(1) + "GHz"
        }
        Meter {
          label: "MEM"
          fraction: root.memPct / 100
          fill: root.critLoad(root.memPct)
          value: Math.round(root.memPct) + "%"
          secondary: root.memUsedGb.toFixed(0) + "/" + root.memTotalGb.toFixed(0) + "G"
        }
        Meter {
          label: "GPU"
          fraction: root.gpuPct / 100
          fill: root.critLoad(root.gpuPct)
          value: root.gpuPct + "%"
        }
        Meter {
          label: "TMP"
          fraction: root.tempC / 100
          fill: root.critTemp(root.tempC)
          value: root.tempC + "°C"
        }
      }

      PanelSeparator {}
      SectionHead { text: "FLUX TELEMETRY" }
      Row {
        width: parent.width
        spacing: Style.spacing.sm
        Column {
          id: fluxLabels
          width: Style.space(34)
          height: flux.height
          FluxLabel { height: flux.height / 4; text: "CPU"; tint: root.critLoad(root.cpuPct) }
          FluxLabel { height: flux.height / 4; text: "MEM"; tint: root.critLoad(root.memPct) }
          FluxLabel { height: flux.height / 4; text: "GPU"; tint: root.critLoad(root.gpuPct) }
          FluxLabel { height: flux.height / 4; text: "TMP"; tint: root.critTemp(root.tempC) }
        }
        Heatmap {
          id: flux
          width: parent.width - fluxLabels.width - parent.spacing
          height: Style.space(88)
          active: panel.visible
          rows: [
            { values: root.cpuHist, max: 100 },
            { values: root.memHist, max: 100 },
            { values: root.gpuHist, max: 100 },
            { values: root.tempHist, max: 100 }
          ]
        }
      }
      // 60 samples at a 5s tick
      Row {
        width: parent.width
        Text {
          width: parent.width / 2
          text: "5 MIN"
          color: Color.menu.text
          opacity: Style.emphasis.faint
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          font.letterSpacing: Style.headerTracking * 0.4
        }
        Text {
          width: parent.width / 2
          horizontalAlignment: Text.AlignRight
          text: "LIVE"
          color: Color.accent
          opacity: Style.emphasis.dim
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          font.letterSpacing: Style.headerTracking * 0.4
        }
      }

      PanelSeparator {}
      SectionHead { text: "HUD READOUT" }
      Text {
        width: parent.width
        visible: root.cpuName.length > 0
        text: root.cpuName + (root.cpuCores > 0 ? " (" + root.cpuCores + " threads)" : "")
        color: Color.menu.text
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        wrapMode: Text.WordWrap
      }
      Text {
        width: parent.width
        visible: root.gpuName.length > 0
        text: root.gpuName
        color: Color.menu.text
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        wrapMode: Text.WordWrap
      }
      Grid {
        width: parent.width
        columns: 2
        spacing: Style.spacing.md
        HudStat { label: "CPU CLK"; value: root.freqMhz + " MHz" }
        HudStat { label: "PKG TEMP"; value: root.tempC + " °C"; tint: root.critTemp(root.tempC) }
        HudStat { visible: root.powerW !== null; label: "POWER (EST.)"; value: Math.round(root.powerW) + " W"
          note: (root.powerW / 1000 * root.pricePerKwh * 100).toFixed(1) + " ct/h" }
        HudStat { visible: root.powerW !== null; label: "SINCE LOGIN"; value: root.energyKwh.toFixed(3) + " kWh"
          note: (root.energyKwh * root.pricePerKwh).toFixed(2) + " €" }
        HudStat { visible: root.cpuPowerW !== null; label: "CPU PWR"; value: Math.round(root.cpuPowerW) + " W" }
        HudStat { visible: root.gpuPowerW !== null; label: "GPU PWR"; value: Math.round(root.gpuPowerW) + " W" }
        HudStat { label: "MEMORY"; value: root.memUsedGb.toFixed(1) + " / " + root.memTotalGb.toFixed(1) + "G" }
        HudStat {
          visible: root.memType !== "" || root.memSpeedMts > 0
          label: "MEM TYPE"
          value: [root.memType, root.memSpeedMts > 0 ? root.memSpeedMts + " MT/s" : ""].filter(function(v) { return v }).join(" · ")
        }
        HudStat { visible: root.memChannels > 0; label: "CHANNELS"; value: root.memChannels + "-CH" }
        HudStat { label: "GPU CLK"; value: root.gpuFreqMhz + " MHz" }
        HudStat {
          visible: root.gpuVendor !== "intel"
          label: "VRAM"
          value: root.vramTotalMb !== null
            ? Math.round(root.vramUsedMb) + " / " + Math.round(root.vramTotalMb) + " MB" : "N/A"
          tint: root.vramTotalMb === null ? Color.menu.text : Color.foreground
        }
        HudStat {
          visible: root.batteryPresent
          label: "BATTERY"
          value: Math.round(root.batteryFraction * 100) + "%" + (root.batteryTime ? " · " + root.batteryTime : "")
        }
        HudStat {
          visible: root.batteryPresent
          label: "STATE"
          value: root.onBattery ? "DISCHARGE" : "CHARGE"
        }
      }

      PanelSeparator {}
      SectionHead { text: "POWER MODE" }

      // overrides are session-only by design
      PowerModeSelector {
        width: parent.width
        active: panel.visible
      }

      PanelSeparator {}
      SectionHead { text: "TOOLS" }

      PanelRow {
        width: parent.width
        // md-harddisk
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

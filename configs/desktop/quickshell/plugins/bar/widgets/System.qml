pragma ComponentBehavior: Bound
import "BatteryModel.js" as BatteryModel
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  // one system-stats.nu line; a key it leaves out or null takes the value here
  readonly property var statsEmpty: ({
    "cpuName": "", "cpuCores": 0, "gpuName": "", "gpuVendor": "", "cpu": 0, "freqMhz": 0, "tempC": 0,
    "memUsedGb": 0, "memTotalGb": 0, "memType": "", "memSpeedMts": 0, "memChannels": 0, "gpuPct": null,
    "gpuFreqMhz": 0, "gpuTempC": null, "powerW": null, "cpuPowerW": null, "gpuPowerW": null, "energyKwh": 0,
    "vramUsedMb": null, "vramTotalMb": null, "top": null
  })
  property var stats: statsEmpty
  readonly property real memPct: stats.memTotalGb > 0 ? stats.memUsedGb / stats.memTotalGb * 100 : 0
  readonly property bool hasGpuPct: stats.gpuPct !== null
  readonly property bool hasVram: stats.gpuVendor !== "intel" && stats.vramTotalMb > 0
  readonly property real vramPct: hasVram ? stats.vramUsedMb / stats.vramTotalMb * 100 : 0
  readonly property real pricePerKwh: 0.35
  property var ossec: null
  property var cpuHist: []
  property var gpuHist: []
  property var memHist: []
  property var tempHist: []
  // the bar sparkline's floor: an idle desktop's few percent stay flat instead of filling the range
  readonly property real cpuSparkFloor: 25
  readonly property var loadThresholds: [60, 80, 92]
  readonly property var tempThresholds: [60, 75, 85]
  readonly property var ossecThresholds: [7, 10, 12]
  readonly property int ossecRetryMs: 60000
  // "clear alerts" writes the unix time here; ossec-alerts.nu watches it and hides every alert up to it
  readonly property string ossecClearedPath: Paths.state + "/ossec-cleared"
  readonly property var batteryDevice: UPower.displayDevice
  readonly property bool batteryPresent: batteryDevice && batteryDevice.isPresent === true
  readonly property bool onBattery: UPower.onBattery === true
  readonly property var upowerStates: ({
    "Charging": UPowerDeviceState.Charging,
    "Discharging": UPowerDeviceState.Discharging,
    "FullyCharged": UPowerDeviceState.FullyCharged,
    "PendingCharge": UPowerDeviceState.PendingCharge
  })
  readonly property real batteryFraction: BatteryModel.batteryFraction(batteryDevice)
  readonly property string batteryIcon: BatteryModel.batteryIcon(batteryDevice, onBattery, upowerStates)
  readonly property string batteryTime: {
    if (!batteryPresent) return ""
    return BatteryModel.formatDuration(onBattery ? batteryDevice.timeToEmpty : batteryDevice.timeToFull)
  }
  readonly property int statsIntervalS: onBattery ? 15 : 10
  // the board's memory as one line: size, type, speed and channels
  readonly property string memSpec: stats.memTotalGb > 0 ? [stats.memTotalGb.toFixed(0) + "G", stats.memType,
    stats.memSpeedMts > 0 ? stats.memSpeedMts + " MT/s" : "", stats.memChannels > 0 ? stats.memChannels + "-CH" : ""]
    .filter(function(v) { return v }).join(" :: ") : ""
  // the history heatmap's rows: the gpu's only while it reports a load
  readonly property var historyRows: [
    { label: "CPU", values: cpuHist, max: 100, tint: critLoad(stats.cpu) },
    { label: "TMP", values: tempHist, max: 100, tint: critTemp(stats.tempC) },
    { label: "MEM", values: memHist, max: 100, tint: critLoad(memPct) }
  ].concat(hasGpuPct ? [{ label: "GPU", values: gpuHist, max: 100, tint: critLoad(stats.gpuPct) }] : [])

  // one used/total form for memory and vram, in GiB like system-stats.nu and the lock screen
  function gib(usedGib, totalGib) {
    return usedGib.toFixed(1) + "/" + totalGib.toFixed(0) + "G"
  }

  function critLoad(pct) {
    return Util.level(pct, loadThresholds)
  }

  function critTemp(t) {
    return Util.level(t, tempThresholds)
  }

  function critLevel(level) {
    return Util.level(level, ossecThresholds)
  }

  moduleName: "system"
  barPriority: 90

  hoverPanel: true

  hoverFill: true
  implicitWidth: label.implicitWidth + Style.bar.itemPaddingX * 2
  implicitHeight: Style.bar.sizeHorizontal
  onStatsIntervalSChanged: {
    statsProc.running = false
    statsRestart.restart()
  }

  Timer {
    id: statsRestart
    interval: 1000
    onTriggered: statsProc.running = true
  }

  Process {
    id: statsProc
    running: true
    command: [Paths.barWidget("system-stats.nu"), String(root.statsIntervalS)]
    onExited: statsRestart.restart()
    Component.onDestruction: {
      statsRestart.stop()
      running = false
    }

    stdout: SplitParser {
      onRead: function(line) {
        let s
        try {
          s = JSON.parse(line)
        } catch (e) {
          return
        }
        for (const key in root.statsEmpty) s[key] = s[key] ?? root.statsEmpty[key];
        root.stats = s
        root.cpuHist = Util.historyPush(root.cpuHist, s.cpu)
        root.gpuHist = Util.historyPush(root.gpuHist, s.gpuPct || 0)
        root.memHist = Util.historyPush(root.memHist, root.memPct)
        root.tempHist = Util.historyPush(root.tempHist, s.tempC)
      }
    }
  }

  FileView {
    id: ossecClearedFile
    path: root.ossecClearedPath
    atomicWrites: true
    printErrors: false
  }

  JsonProcess {
    command: [Paths.barWidget("ossec-alerts.nu"), root.ossecClearedPath]
    streaming: true
    running: true
    // restart the stream when it exits: the script returns at once while ossec-server.target is down, so a long
    // retry keeps a machine without ossec from spawning nu every few seconds
    intervalMs: root.ossecRetryMs
    onParsed: function(data) {
      root.ossec = data
    }
  }

  Row {
    id: label
    anchors.centerIn: parent
    spacing: Style.spacing.sm

    Sparkline {
      pulsing: false
      anchors.verticalCenter: parent.verticalCenter
      width: Style.space(40)
      height: Style.space(14)
      values: root.cpuHist
      maxValue: Math.max(root.cpuSparkFloor, ...root.cpuHist)
    }

    Stat {
      glyph: "\u{f035b}"
      widest: "100%"
      value: root.stats.cpu + "%"
    }

    Stat {
      glyph: "\u{f050f}"
      widest: "100\u00b0C"
      value: root.stats.tempC + "\u00b0C"
    }

    Stat {
      glyph: "\u{efc5}"
      widest: root.gib(root.stats.memTotalGb, root.stats.memTotalGb)
      value: root.gib(root.stats.memUsedGb, root.stats.memTotalGb)
    }

    Stat {
      visible: root.hasGpuPct
      glyph: "\u{f08ae}"
      widest: "100%"
      value: root.stats.gpuPct + "%"
    }

    Stat {
      visible: root.hasVram
      glyph: "\u{f061a}"
      widest: root.gib(root.stats.vramTotalMb / 1024, root.stats.vramTotalMb / 1024)
      value: root.gib(root.stats.vramUsedMb / 1024, root.stats.vramTotalMb / 1024)
    }

    Stat {
      visible: root.batteryPresent
      glyph: root.batteryIcon
      widest: "100%"
      value: Math.round(root.batteryFraction * 100) + "%"
    }

    Stat {
      visible: root.ossec !== null && root.ossec.high > 0
      glyph: "\u{f0ce4}"
      widest: "99"
      value: root.ossec ? root.ossec.high : ""
      tint: Colors.semantic.live
      glyphTint: Colors.semantic.live
    }
  }

  HoverPanel {
    id: panel
    anchorWidget: root
    title: "SYSTEM"
    implicitWidth: Style.panelWidth.normal

    Column {
      id: content
      width: parent.width
      spacing: Style.spacing.sm

      Column {
        width: parent.width
        spacing: Style.spacing.xs

        Meter {
          label: "CPU"
          fraction: root.stats.cpu / 100
          tint: root.critLoad(root.stats.cpu)
          value: root.stats.cpu + "%"
          note: (root.stats.freqMhz / 1000).toFixed(1) + "GHz"
        }

        Meter {
          label: "TMP"
          fraction: root.stats.tempC / 100
          tint: root.critTemp(root.stats.tempC)
          value: root.stats.tempC + "\u00b0C"
        }

        Meter {
          label: "MEM"
          fraction: root.memPct / 100
          tint: root.critLoad(root.memPct)
          value: Math.round(root.memPct) + "%"
          note: root.gib(root.stats.memUsedGb, root.stats.memTotalGb)
        }

        Meter {
          visible: root.hasGpuPct
          label: "GPU"
          fraction: root.stats.gpuPct / 100
          tint: root.critLoad(root.stats.gpuPct)
          value: root.stats.gpuPct + "%"
          note: (root.stats.gpuFreqMhz / 1000).toFixed(1) + "GHz"
        }

        Meter {
          visible: root.hasVram
          label: "VRAM"
          fraction: root.vramPct / 100
          tint: root.critLoad(root.vramPct)
          value: Math.round(root.vramPct) + "%"
          note: root.gib(root.stats.vramUsedMb / 1024, root.stats.vramTotalMb / 1024)
        }
      }

      PanelSeparator { visible: historySection.visible }

      // one sample draws a single column: the history waits for a second one
      Column {
        id: historySection
        visible: root.cpuHist.length > 1
        width: parent.width
        spacing: Style.spacing.sm

        PanelSectionHeader { text: "HISTORY" }

        Row {
          width: parent.width
          spacing: Style.spacing.xs

          Column {
            id: fluxLabels
            Repeater {
              model: root.historyRows

              Item {
                id: fluxRow
                required property var modelData

                width: fluxLabel.implicitWidth
                height: flux.height / root.historyRows.length

                PanelSectionHeader {
                  id: fluxLabel
                  anchors.verticalCenter: parent.verticalCenter
                  text: fluxRow.modelData.label
                  foreground: fluxRow.modelData.tint
                }
              }
            }
          }

          Heatmap {
            id: flux
            width: parent.width - fluxLabels.width - parent.spacing
            height: Style.space(22) * root.historyRows.length
            active: panel.visible
            rows: root.historyRows
          }
        }

        Row {
          width: parent.width

          Label {
            width: parent.width / 2
            text: Math.round(Util.historyCountMax * root.statsIntervalS / 60) + " MIN"
            dim: true
            caption: true
            font.letterSpacing: Style.labelTracking
          }

          Label {
            width: parent.width / 2
            horizontalAlignment: Text.AlignRight
            text: "LIVE"
            color: Colors.accentText
            caption: true
            font.letterSpacing: Style.labelTracking
          }
        }
      }

      PanelSeparator {}

      PanelSectionHeader { text: "HARDWARE" }

      HardwareLine {
        visible: root.stats.cpuName.length > 0
        text: root.stats.cpuName + (root.stats.cpuCores > 0 ? " (" + root.stats.cpuCores + " threads)" : "")
      }

      HardwareLine {
        visible: root.stats.gpuName.length > 0
        text: root.stats.gpuName + (root.stats.gpuVendor === "intel" ? " (shared memory)" : "")
      }

      HardwareLine {
        visible: root.memSpec.length > 0
        text: root.memSpec
      }

      Grid {
        width: parent.width
        columns: 2
        spacing: Style.spacing.sm

        // the clocks, the cpu temperature, memory and vram are in the meters above; these are what they leave out
        HudStat {
          visible: !root.hasGpuPct && root.stats.gpuFreqMhz > 0
          label: "GPU CLK"
          value: root.stats.gpuFreqMhz + " MHz"
        }

        HudStat {
          visible: root.stats.gpuTempC !== null
          label: "GPU TEMP"
          value: root.stats.gpuTempC + "\u00b0C"
          tint: root.critTemp(root.stats.gpuTempC)
        }

        HudStat {
          visible: root.stats.cpuPowerW !== null || root.stats.gpuPowerW !== null
          label: "CPU PWR"
          value: root.stats.cpuPowerW !== null ? Math.round(root.stats.cpuPowerW) + " W" : "--"
        }

        HudStat {
          visible: root.stats.cpuPowerW !== null || root.stats.gpuPowerW !== null
          label: "GPU PWR"
          value: root.stats.gpuPowerW !== null ? Math.round(root.stats.gpuPowerW) + " W" : "--"
        }

        HudStat {
          visible: root.stats.powerW !== null
          label: "POWER (EST.)"
          value: Math.round(root.stats.powerW) + " W"
          note: (root.stats.powerW / 1000 * root.pricePerKwh * 100).toFixed(1) + " ct/h"
        }

        HudStat {
          visible: root.stats.powerW !== null
          label: "SINCE LOGIN"
          value: root.stats.energyKwh.toFixed(3) + " kWh"
          note: (root.stats.energyKwh * root.pricePerKwh).toFixed(2) + " \u20ac"
        }

        HudStat {
          visible: root.batteryPresent
          label: "BATTERY"
          value: Math.round(root.batteryFraction * 100) + "%" + (root.batteryTime ? " :: " + root.batteryTime : "")
          note: root.onBattery ? "DISCHARGE" : "CHARGE"
        }
      }

      Column {
        visible: root.stats.top !== null
        width: parent.width
        spacing: Style.spacing.sm

        PanelSeparator {}

        PanelSectionHeader { text: "TOP PROCESSES" }

        Row {
          id: procSplit
          width: parent.width
          spacing: Style.spacing.sm

          Repeater {
            model: [{
              "head": "CPU",
              "items": root.stats.top ? root.stats.top.cpu : []
            }, {
              "head": "MEM",
              "items": root.stats.top ? root.stats.top.mem : []
            }]

            Column {
              required property var modelData

              width: (procSplit.width - procSplit.spacing) / 2
              spacing: Style.spacing.hair

              Label {
                text: parent.modelData.head
                color: Colors.menu.text
                caption: true
                font.capitalization: Font.AllUppercase
                font.letterSpacing: Style.labelTracking
              }

              Repeater {
                model: parent.modelData.items

                Row {
                  id: procRow
                  required property var modelData

                  width: parent ? parent.width : 0
                  spacing: Style.spacing.xs

                  Label {
                    width: parent.width - procPct.width - parent.spacing
                    text: procRow.modelData.name
                    elide: Text.ElideRight
                    opacity: Style.emphasis.strong
                    caption: true
                  }

                  Label {
                    id: procPct
                    width: Style.space(44)
                    text: (procRow.modelData.pct >= 100 ? Math.round(procRow.modelData.pct) : procRow.modelData.pct.toFixed(1)) + "%"
                    horizontalAlignment: Text.AlignRight
                    dim: true
                    caption: true
                    font.features: {
                      "tnum": 1
                    }
                  }
                }
              }
            }
          }
        }
      }

      Column {
        visible: root.ossec !== null && root.ossec.total > 0
        width: parent.width
        spacing: Style.spacing.sm

        PanelSeparator {}

        PanelSectionHeader { text: "ALERTS" }

        Meter {
          label: "24H"
          value: root.ossec ? String(root.ossec.total) : ""
          note: root.ossec ? "max L" + root.ossec.maxLevel : ""
          tint: root.critLevel(root.ossec ? root.ossec.maxLevel : 0)
        }

        PanelRow {
          width: parent.width
          glyph: "\u{f0e2a}"
          label: "Clear alerts"
          onActivated: ossecClearedFile.setText(Math.floor(Date.now() / 1000) + "\n")
        }

        Column {
          width: parent.width
          spacing: Style.spacing.xs

          Repeater {
            model: root.ossec ? root.ossec.recent : []

            Row {
              id: alertRow
              required property var modelData

              width: parent.width
              spacing: Style.spacing.xs

              Label {
                id: alertLevel
                width: Style.space(28)
                text: "L" + alertRow.modelData.level
                color: Colors.textFor(root.critLevel(alertRow.modelData.level))
                caption: true
                font.bold: true
                layer.enabled: Style.fx.glow > 0

                layer.effect: Glow {
                  shadowColor: alertLevel.color
                }
              }

              Label {
                width: parent.width - alertLevel.width - alertTime.width - parent.spacing * 2
                text: alertRow.modelData.desc
                elide: Text.ElideRight
                opacity: Style.emphasis.strong
                caption: true
              }

              Label {
                id: alertTime
                text: alertRow.modelData.t
                dim: true
                caption: true
              }
            }
          }
        }
      }

      PanelSeparator {}

      PanelSectionHeader { text: "POWER MODE" }

      PowerModeSelector {
        width: parent.width
        active: panel.visible
      }

      PanelSeparator {}

      PanelSectionHeader { text: "TOOLS" }

      PanelRow {
        width: parent.width
        glyph: "\u{f02ca}"
        label: "Disk speed test"
        onActivated: {
          if (root.bar) root.bar.closePanel(root.moduleName)
          Quickshell.execDetached(Paths.ipcCall("shell", "summon", "panel.speedtest", "{\"mode\":\"disk\"}"))
        }
      }
    }
  }

  component Stat: Row {
    id: stat
    property string glyph: ""
    property string value: ""
    property string widest: ""
    property color tint: Colors.bar.text
    property color glyphTint: Colors.textDim

    spacing: Style.spacing.xs

    Label {
      anchors.verticalCenter: parent.verticalCenter
      text: parent.glyph
      color: parent.glyphTint
      icon: true
      font.pixelSize: Style.font.icon
    }

    Label {
      id: slotText
      anchors.verticalCenter: parent.verticalCenter
      width: Math.ceil(sizer.implicitWidth)
      text: parent.value
      color: Colors.textFor(parent.tint)
      font.letterSpacing: Style.displayTracking

      Text {
        id: sizer
        visible: false
        textFormat: Text.PlainText
        text: stat.widest
        font.family: slotText.font.family
        font.pixelSize: slotText.font.pixelSize
      }
    }
  }

  component HardwareLine: Label {
    width: parent.width
    color: Colors.menu.text
    caption: true
    wrapMode: Text.WordWrap
  }

  component HudStat: MetricRow {
    width: parent ? (parent.width - (parent as Grid).spacing) / 2 : 0
    valueSize: Style.font.title
  }

  component Meter: MetricRow {
    valueBeside: true
  }
}

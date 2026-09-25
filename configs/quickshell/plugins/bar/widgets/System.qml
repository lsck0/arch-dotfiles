import QtQuick
import QtQuick.Effects
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

  // Rolling history for the panel sparklines (newest last, capped).
  property var cpuHist: []
  property var gpuHist: []
  property var memHist: []
  property var tempHist: []
  function _push(arr, v) { var a = arr.slice(); a.push(v); if (a.length > 60) a.shift(); return a }

  // Reactor criticality: nominal -> elevated -> high -> critical, mapped to the shell's semantic colours.
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
  function tempState(t) {
    if (t >= 85) return "CRITICAL"
    if (t >= 75) return "HIGH"
    if (t >= 60) return "ELEVATED"
    return "NOMINAL"
  }

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
          root.cpuHist = root._push(root.cpuHist, root.cpuPct)
          root.gpuHist = root._push(root.gpuHist, root.gpuPct)
          root.memHist = root._push(root.memHist, root.memTotalGb > 0 ? root.memUsedGb / root.memTotalGb * 100 : 0)
          root.tempHist = root._push(root.tempHist, root.tempC)
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
      // Tight tracking + subtle accent bloom on the mono stat readout.
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

    // Live CPU-history sparkline right on the bar, hidden on a vertical bar where a wide graph does not fit.
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
    onEntered: if (root.bar) root.bar.hoverOpen(root.moduleName)
    onExited: if (root.bar) root.bar.hoverTriggerExit(root.moduleName)
  }

  // A terminal-style readout row: uppercase tracked key on the left, bright mono value flush right.
  component Row_: Row {
    property string label: ""
    property string value: ""
    property bool dim: false
    width: parent ? parent.width : 0
    spacing: Style.spacing.sm
    Text {
      width: Math.round((parent.width - parent.spacing) * 0.42)
      text: parent.label
      color: Color.menu.text
      opacity: Style.emphasis.dim
      elide: Text.ElideRight
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      font.capitalization: Font.AllUppercase
      font.letterSpacing: Style.headerTracking * 0.4
    }
    Text {
      width: Math.round((parent.width - parent.spacing) * 0.58)
      horizontalAlignment: Text.AlignRight
      text: parent.value
      color: Color.foreground
      opacity: parent.dim ? Style.emphasis.faint : Style.emphasis.strong
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      font.letterSpacing: Style.displayTracking
    }
  }

  // Bracket-framed section head: accent block glyph, tracked uppercase label, phosphor rule filling the row.
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

  // One HUD telemetry cell: tracked uppercase key stacked over a bright mono value. Sized to fit a two-column Grid.
  component HudStat: Column {
    property string label: ""
    property string value: ""
    property color tint: Color.foreground
    width: parent ? (parent.width - parent.spacing) / 2 : 0
    spacing: Style.spacing.hairline
    Text {
      text: parent.label
      color: Color.menu.text
      opacity: Style.emphasis.dim
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
  }

  // One labelled row in the flux heatmap's left gutter, height matched to a heatmap band.
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

      // Terminal-window title strip: prompt, panel name, blinking block caret, decorative window chrome.
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
            layer.effect: MultiEffect {
              shadowEnabled: true
              shadowColor: Style.fx.glowColor
              shadowBlur: 1.0
              shadowVerticalOffset: 0
              shadowHorizontalOffset: 0
              blurMax: Style.fx.glowRadius
              autoPaddingEnabled: true
            }
            SequentialAnimation on opacity {
              running: true
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

      // ---- REACTOR CORE ------------------------------------------------- Core temperature is the reactor's criticality; CPU/MEM/GPU orbit as containment gauges.
      Item {
        id: reactor
        width: parent.width
        height: Style.space(228)
        readonly property real cx: width / 2
        readonly property real cy: height / 2
        readonly property real orbit: Style.space(88)
        readonly property int satSize: Style.space(50)
        readonly property real heatFrac: Math.max(0, Math.min(1, root.tempC / 100))
        readonly property color coreColor: root.critTemp(root.tempC)

        // Containment ring + plasma core, centred.
        Item {
          id: coreBox
          width: Style.space(108)
          height: width
          anchors.centerIn: parent

          // Outer containment ring gauge, sweeping the core temperature.
          RadialGauge {
            anchors.fill: parent
            active: panel.visible
            value: reactor.heatFrac
            color: reactor.coreColor
            trackColor: Util.alpha(Color.foreground, 0.12)
            thickness: Style.space(5)
            startAngle: 130
            sweepAngle: 280
            ticks: 24
          }

          // Plasma bloom: a soft glowing disc whose size + tint track core heat.
          Rectangle {
            id: halo
            anchors.centerIn: parent
            width: coreBox.width * (0.42 + 0.20 * reactor.heatFrac)
            height: width
            radius: width / 2
            color: Util.alpha(reactor.coreColor, 0.10 + 0.16 * reactor.heatFrac)
            Behavior on width { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }
            Behavior on color { ColorAnimation { duration: 400 } }
            layer.enabled: Style.fx.glow > 0
            layer.effect: MultiEffect {
              shadowEnabled: true
              shadowColor: reactor.coreColor
              shadowBlur: 1.0
              shadowVerticalOffset: 0
              shadowHorizontalOffset: 0
              blurMax: Style.fx.glowRadius * 2
              autoPaddingEnabled: true
            }
          }

          // Core readout: big temperature numeral, unit, and criticality state word.
          Column {
            anchors.centerIn: parent
            spacing: 0
            Row {
              anchors.horizontalCenter: parent.horizontalCenter
              spacing: Style.spacing.xxs
              Text {
                id: coreNum
                anchors.bottom: parent.bottom
                text: root.tempC
                color: reactor.coreColor
                font.family: Style.font.family
                font.pixelSize: Style.font.display
                font.bold: true
                font.letterSpacing: Style.displayTracking
                Behavior on color { ColorAnimation { duration: 400 } }
                layer.enabled: Style.fx.glow > 0
                layer.effect: MultiEffect {
                  shadowEnabled: true
                  shadowColor: reactor.coreColor
                  shadowBlur: 1.0
                  shadowVerticalOffset: 0
                  shadowHorizontalOffset: 0
                  blurMax: Style.fx.glowRadius
                  autoPaddingEnabled: true
                }
              }
              Text {
                anchors.bottom: coreNum.bottom
                anchors.bottomMargin: Math.round(Style.font.display * 0.16)
                text: "°C"
                color: reactor.coreColor
                opacity: Style.emphasis.dim
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
              }
            }
            Text {
              anchors.horizontalCenter: parent.horizontalCenter
              text: root.tempState(root.tempC)
              color: reactor.coreColor
              opacity: Style.emphasis.dim
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              font.bold: true
              font.capitalization: Font.AllUppercase
              font.letterSpacing: Style.headerTracking * 0.5
            }
          }
        }

        // CPU satellite (upper-left orbit).
        RadialGauge {
          width: reactor.satSize; height: reactor.satSize
          x: reactor.cx + reactor.orbit * Math.cos(210 * Math.PI / 180) - width / 2
          y: reactor.cy + reactor.orbit * Math.sin(210 * Math.PI / 180) - height / 2
          active: panel.visible
          value: root.cpuPct / 100
          color: root.critLoad(root.cpuPct)
          thickness: Style.space(3)
          ticks: 12
          text: root.cpuPct + "%"
          subText: "CPU"
          textSize: Style.font.body
        }
        // GPU satellite (upper-right orbit).
        RadialGauge {
          width: reactor.satSize; height: reactor.satSize
          x: reactor.cx + reactor.orbit * Math.cos(330 * Math.PI / 180) - width / 2
          y: reactor.cy + reactor.orbit * Math.sin(330 * Math.PI / 180) - height / 2
          active: panel.visible
          value: root.gpuPct / 100
          color: root.critLoad(root.gpuPct)
          thickness: Style.space(3)
          ticks: 12
          text: root.gpuPct + "%"
          subText: "GPU"
          textSize: Style.font.body
        }
        // MEM satellite (lower orbit).
        RadialGauge {
          width: reactor.satSize; height: reactor.satSize
          x: reactor.cx + reactor.orbit * Math.cos(90 * Math.PI / 180) - width / 2
          y: reactor.cy + reactor.orbit * Math.sin(90 * Math.PI / 180) - height / 2
          active: panel.visible
          value: root.memTotalGb > 0 ? root.memUsedGb / root.memTotalGb : 0
          color: root.critLoad(root.memTotalGb > 0 ? root.memUsedGb / root.memTotalGb * 100 : 0)
          thickness: Style.space(3)
          ticks: 12
          text: root.memTotalGb > 0 ? Math.round(root.memUsedGb / root.memTotalGb * 100) + "%" : "0%"
          subText: "MEM"
          textSize: Style.font.body
        }
      }

      PanelSeparator {}
      SectionHead { text: "FLUX TELEMETRY" }
      // Scrolling waterfall: one history band per subsystem, hottest cells map to criticality colours.
      Row {
        width: parent.width
        spacing: Style.spacing.sm
        Column {
          id: fluxLabels
          width: Style.space(34)
          height: flux.height
          FluxLabel { height: flux.height / 4; text: "CPU"; tint: root.critLoad(root.cpuPct) }
          FluxLabel { height: flux.height / 4; text: "MEM"; tint: root.critLoad(root.memTotalGb > 0 ? root.memUsedGb / root.memTotalGb * 100 : 0) }
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
      // Time axis: oldest sample left, live edge right (60 samples at a ~5s tick).
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
        opacity: Style.emphasis.dim
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        wrapMode: Text.WordWrap
      }
      Text {
        width: parent.width
        visible: root.gpuName.length > 0
        text: root.gpuName
        color: Color.menu.text
        opacity: Style.emphasis.dim
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        wrapMode: Text.WordWrap
      }
      // Two-column mono readout matrix. Invisible cells collapse out of the grid.
      Grid {
        id: hudGrid
        width: parent.width
        columns: 2
        spacing: Style.spacing.md
        HudStat { label: "CPU CLK"; value: root.freqMhz + " MHz" }
        HudStat { label: "PKG TEMP"; value: root.tempC + " °C"; tint: root.critTemp(root.tempC) }
        HudStat { visible: root.powerW !== null; label: "PKG PWR"; value: root.powerW + " W" }
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

      // Any override made here is deliberately session-only: it never survives a reboot, matching the requested "overridable but non-persistent" policy.
      PowerModeSelector {
        width: parent.width
        active: panel.visible
      }

      PanelSeparator {}
      SectionHead { text: "TOOLS" }

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

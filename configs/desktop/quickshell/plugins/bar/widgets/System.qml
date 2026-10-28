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
    readonly property bool hasVram: gpuVendor !== "intel" && vramTotalMb !== null && vramTotalMb > 0
    readonly property real vramPct: hasVram ? vramUsedMb / vramTotalMb * 100 : 0
    property string memType: ""
    property int memSpeedMts: 0
    property int memChannels: 0
    property int gpuPct: 0
    property bool hasGpuPct: false
    property int gpuFreqMhz: 0
    property var gpuTempC: null
    property var powerW: null
    property var cpuPowerW: null
    property var gpuPowerW: null
    property real energyKwh: 0
    readonly property real pricePerKwh: 0.35
    property var vramUsedMb: null
    property var vramTotalMb: null
    property var ossec: null
    property var topProc: null
    property var cpuHist: []
    property var gpuHist: []
    property var memHist: []
    property var tempHist: []
    readonly property var loadThresholds: [60, 80, 92]
    readonly property var tempThresholds: [60, 75, 85]
    readonly property var ossecThresholds: [7, 10, 12]
    readonly property int ossecRetryMs: 5000
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
        if (!batteryPresent)
            return "";

        return BatteryModel.formatDuration(onBattery ? batteryDevice.timeToEmpty : batteryDevice.timeToFull);
    }
    readonly property int statsIntervalS: onBattery ? 15 : 10

    function critLoad(pct) {
        return Util.level(pct, loadThresholds);
    }

    function critTemp(t) {
        return Util.level(t, tempThresholds);
    }

    function critLevel(level) {
        return Util.level(level, ossecThresholds);
    }

    moduleName: "system"

    hoverPanel: true

    hoverFill: true
    implicitWidth: label.implicitWidth + Style.bar.itemPaddingX * 2
    implicitHeight: barSize
    onStatsIntervalSChanged: {
        statsProc.running = false;
        statsRestart.restart();
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
            statsRestart.stop();
            running = false;
        }

        stdout: SplitParser {
            splitMarker: "\n"
            onRead: function(line) {
                if (!line)
                    return ;

                try {
                    let s = JSON.parse(line);
                    root.cpuName = s.cpuName || "";
                    root.cpuCores = s.cpuCores || 0;
                    root.gpuName = s.gpuName || "";
                    root.gpuVendor = s.gpuVendor || "";
                    root.cpuPct = s.cpu || 0;
                    root.freqMhz = s.freqMhz || 0;
                    root.tempC = s.tempC || 0;
                    root.memUsedGb = s.memUsedGb || 0;
                    root.memTotalGb = s.memTotalGb || 0;
                    root.memType = s.memType || "";
                    root.memSpeedMts = s.memSpeedMts || 0;
                    root.memChannels = s.memChannels || 0;
                    root.hasGpuPct = s.gpuPct !== null && s.gpuPct !== undefined;
                    root.gpuPct = s.gpuPct || 0;
                    root.gpuFreqMhz = s.gpuFreqMhz || 0;
                    root.gpuTempC = (s.gpuTempC === undefined) ? null : s.gpuTempC;
                    root.powerW = (s.powerW === undefined) ? null : s.powerW;
                    root.cpuPowerW = (s.cpuPowerW === undefined) ? null : s.cpuPowerW;
                    root.gpuPowerW = (s.gpuPowerW === undefined) ? null : s.gpuPowerW;
                    root.energyKwh = s.energyKwh || 0;
                    root.vramUsedMb = (s.vramUsedMb === undefined) ? null : s.vramUsedMb;
                    root.vramTotalMb = (s.vramTotalMb === undefined) ? null : s.vramTotalMb;
                    root.topProc = (s.top === undefined) ? null : s.top;
                    root.cpuHist = Util.historyPush(root.cpuHist, root.cpuPct);
                    root.gpuHist = Util.historyPush(root.gpuHist, root.gpuPct);
                    root.memHist = Util.historyPush(root.memHist, root.memPct);
                    root.tempHist = Util.historyPush(root.tempHist, root.tempC);
                } catch (e) {
                }
            }
        }

    }

    JsonProcess {
        command: [Paths.barWidget("ossec-alerts.nu")]
        streaming: true
        running: true
        // restart the stream when it exits: the script returns at once while ossec-server.target is down
        intervalMs: root.ossecRetryMs
        onParsed: function(data) {
            root.ossec = data;
        }
    }

    Row {
        id: label

        anchors.centerIn: parent
        spacing: Style.spacing.sm

        Sparkline {
            visible: !root.vertical
            pulsing: false
            anchors.verticalCenter: parent.verticalCenter
            width: Style.space(40)
            height: Style.space(14)
            values: root.cpuHist
            minValue: 0
            maxValue: 100
            color: Colors.accent
        }

        Stat {
            glyph: "\u{f035b}"
            widest: "100%"
            value: root.cpuPct + "%"
        }

        Stat {
            glyph: "\u{f050f}"
            widest: "100\u00b0C"
            value: root.tempC + "\u00b0C"
        }

        Stat {
            glyph: "\u{efc5}"
            widest: root.memTotalGb.toFixed(1) + "/" + root.memTotalGb.toFixed(0) + "G"
            value: root.memUsedGb.toFixed(1) + "/" + root.memTotalGb.toFixed(0) + "G"
        }

        Stat {
            visible: root.hasGpuPct
            glyph: "\u{f08ae}"
            widest: "100%"
            value: root.gpuPct + "%"
        }

        Stat {
            visible: root.hasVram
            glyph: "\u{f061a}"
            widest: (root.vramTotalMb / 1024).toFixed(1) + "/" + (root.vramTotalMb / 1024).toFixed(1) + "G"
            value: (root.vramUsedMb / 1024).toFixed(1) + "/" + (root.vramTotalMb / 1024).toFixed(1) + "G"
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
        }

    }

    HoverPanel {
        id: panel
        anchorWidget: root
        title: "SYSTEM"
        implicitWidth: Style.panelWidth.normal
        implicitHeight: Math.min(content.implicitHeight, maxBodyHeight) + padding * 2 + titleInset

        Flickable {
            width: parent.width
            height: Math.min(content.implicitHeight, panel.maxBodyHeight)
            contentWidth: width
            contentHeight: content.implicitHeight
            interactive: contentHeight > height
            boundsBehavior: Flickable.StopAtBounds
            clip: true

            Column {
                id: content

                width: parent.width
                spacing: Style.spacing.sm

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
                        label: "TMP"
                        fraction: root.tempC / 100
                        fill: root.critTemp(root.tempC)
                        value: root.tempC + "\u00b0C"
                    }

                    Meter {
                        label: "MEM"
                        fraction: root.memPct / 100
                        fill: root.critLoad(root.memPct)
                        value: Math.round(root.memPct) + "%"
                        secondary: root.memUsedGb.toFixed(0) + "/" + root.memTotalGb.toFixed(0) + "G"
                    }

                    Meter {
                        visible: root.hasGpuPct
                        label: "GPU"
                        fraction: root.gpuPct / 100
                        fill: root.critLoad(root.gpuPct)
                        value: root.gpuPct + "%"
                        secondary: (root.gpuFreqMhz / 1000).toFixed(1) + "GHz"
                    }

                    Meter {
                        visible: root.hasVram
                        label: "VRAM"
                        fraction: root.vramPct / 100
                        fill: root.critLoad(root.vramPct)
                        value: Math.round(root.vramPct) + "%"
                        secondary: (root.vramUsedMb / 1024).toFixed(0) + "/" + (root.vramTotalMb / 1024).toFixed(0) + "G"
                    }

                }

                PanelSeparator {
                }

                SectionHead {
                    text: "HISTORY"
                }

                Row {
                    width: parent.width
                    spacing: Style.spacing.xs

                    Column {
                        id: fluxLabels

                        width: Style.space(34)
                        height: flux.height

                        FluxLabel {
                            height: flux.height / 4
                            text: "CPU"
                            tint: root.critLoad(root.cpuPct)
                        }

                        FluxLabel {
                            height: flux.height / 4
                            text: "TMP"
                            tint: root.critTemp(root.tempC)
                        }

                        FluxLabel {
                            height: flux.height / 4
                            text: "MEM"
                            tint: root.critLoad(root.memPct)
                        }

                        FluxLabel {
                            height: flux.height / 4
                            text: "GPU"
                            tint: root.critLoad(root.gpuPct)
                        }

                    }

                    Heatmap {
                        id: flux

                        width: parent.width - fluxLabels.width - parent.spacing
                        height: Style.space(88)
                        active: panel.visible
                        rows: [{
                            "values": root.cpuHist,
                            "max": 100
                        }, {
                            "values": root.tempHist,
                            "max": 100
                        }, {
                            "values": root.memHist,
                            "max": 100
                        }, {
                            "values": root.gpuHist,
                            "max": 100
                        }]
                    }

                }

                Row {
                    width: parent.width

                    Text {
                        width: parent.width / 2
                        text: Math.round(Util.historyCountMax * root.statsIntervalS / 60) + " MIN"
                        color: Colors.menu.text
                        opacity: Style.emphasis.faint
                        font.family: Style.font.family
                        font.pixelSize: Style.font.caption
                        font.letterSpacing: Style.labelTracking
                    }

                    Text {
                        width: parent.width / 2
                        horizontalAlignment: Text.AlignRight
                        text: "LIVE"
                        color: Colors.accent
                        opacity: Style.emphasis.dim
                        font.family: Style.font.family
                        font.pixelSize: Style.font.caption
                        font.letterSpacing: Style.labelTracking
                    }

                }

                PanelSeparator {
                }

                SectionHead {
                    text: "HARDWARE"
                }

                Text {
                    width: parent.width
                    visible: root.cpuName.length > 0
                    text: root.cpuName + (root.cpuCores > 0 ? " (" + root.cpuCores + " threads)" : "")
                    color: Colors.menu.text
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption
                    wrapMode: Text.WordWrap
                }

                Text {
                    width: parent.width
                    visible: root.gpuName.length > 0
                    text: root.gpuName
                    color: Colors.menu.text
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption
                    wrapMode: Text.WordWrap
                }

                Grid {
                    width: parent.width
                    columns: 2
                    spacing: Style.spacing.sm

                    HudStat {
                        label: "CPU CLK"
                        value: root.freqMhz + " MHz"
                    }

                    HudStat {
                        label: "GPU CLK"
                        value: root.gpuFreqMhz + " MHz"
                    }

                    HudStat {
                        label: "CPU TEMP"
                        value: root.tempC + " \u00b0C"
                        tint: root.critTemp(root.tempC)
                    }

                    HudStat {
                        label: "GPU TEMP"
                        value: root.gpuTempC !== null ? root.gpuTempC + " \u00b0C" : "--"
                        tint: root.gpuTempC !== null ? root.critTemp(root.gpuTempC) : Colors.menu.text
                    }

                    HudStat {
                        visible: root.cpuPowerW !== null || root.gpuPowerW !== null
                        label: "CPU PWR"
                        value: root.cpuPowerW !== null ? Math.round(root.cpuPowerW) + " W" : "--"
                    }

                    HudStat {
                        visible: root.cpuPowerW !== null || root.gpuPowerW !== null
                        label: "GPU PWR"
                        value: root.gpuPowerW !== null ? Math.round(root.gpuPowerW) + " W" : "--"
                    }

                    HudStat {
                        label: "MEMORY"
                        value: root.memUsedGb.toFixed(1) + " / " + root.memTotalGb.toFixed(1) + "G"
                        note: [root.memType, root.memSpeedMts > 0 ? root.memSpeedMts + " MT/s" : "", root.memChannels > 0 ? root.memChannels + "-CH" : ""].filter(function(v) {
                            return v;
                        }).join(" :: ")
                    }

                    HudStat {
                        label: "VRAM"
                        value: root.hasVram ? (root.vramUsedMb / 1024).toFixed(1) + " / " + (root.vramTotalMb / 1024).toFixed(1) + "G" : (root.gpuVendor === "intel" ? "shared" : "--")
                        note: root.hasVram ? Math.round(root.vramPct) + "%" : ""
                    }

                    HudStat {
                        visible: root.powerW !== null
                        label: "POWER (EST.)"
                        value: Math.round(root.powerW) + " W"
                        note: (root.powerW / 1000 * root.pricePerKwh * 100).toFixed(1) + " ct/h"
                    }

                    HudStat {
                        visible: root.powerW !== null
                        label: "SINCE LOGIN"
                        value: root.energyKwh.toFixed(3) + " kWh"
                        note: (root.energyKwh * root.pricePerKwh).toFixed(2) + " \u20ac"
                    }

                    HudStat {
                        visible: root.batteryPresent
                        label: "BATTERY"
                        value: Math.round(root.batteryFraction * 100) + "%" + (root.batteryTime ? " :: " + root.batteryTime : "")
                    }

                    HudStat {
                        visible: root.batteryPresent
                        label: "STATE"
                        value: root.onBattery ? "DISCHARGE" : "CHARGE"
                    }

                }

                Column {
                    visible: root.topProc !== null
                    width: parent.width
                    spacing: Style.spacing.sm

                    PanelSeparator {
                    }

                    SectionHead {
                        text: "TOP PROCESSES"
                    }

                    Row {
                        id: procSplit
                        width: parent.width
                        spacing: Style.spacing.sm

                        Repeater {
                            model: [{
                                "head": "CPU",
                                "items": root.topProc ? root.topProc.cpu : []
                            }, {
                                "head": "MEM",
                                "items": root.topProc ? root.topProc.mem : []
                            }]

                            Column {
                                required property var modelData

                                width: (procSplit.width - procSplit.spacing) / 2
                                spacing: Style.spacing.hair

                                Text {
                                    text: parent.modelData.head
                                    color: Colors.menu.text
                                    font.family: Style.font.family
                                    font.pixelSize: Style.font.caption
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

                                        Text {
                                            width: parent.width - procPct.width - parent.spacing
                                            text: procRow.modelData.name
                                            elide: Text.ElideRight
                                            color: Colors.foreground
                                            opacity: Style.emphasis.strong
                                            font.family: Style.font.family
                                            font.pixelSize: Style.font.caption
                                        }

                                        Text {
                                            id: procPct

                                            width: Style.space(44)
                                            text: (procRow.modelData.pct >= 100 ? Math.round(procRow.modelData.pct) : procRow.modelData.pct.toFixed(1)) + "%"
                                            horizontalAlignment: Text.AlignRight
                                            color: Colors.menu.text
                                            opacity: Style.emphasis.dim
                                            font.family: Style.font.family
                                            font.pixelSize: Style.font.caption
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
                    visible: root.ossec !== null
                    width: parent.width
                    spacing: Style.spacing.sm

                    PanelSeparator {
                    }

                    SectionHead {
                        text: "ALERTS"
                    }

                    Grid {
                        width: parent.width
                        columns: 2
                        spacing: Style.spacing.sm

                        HudStat {
                            label: "24H"
                            value: root.ossec ? root.ossec.total : ""
                        }

                        HudStat {
                            label: "MAX LEVEL"
                            value: root.ossec ? root.ossec.maxLevel : ""
                            tint: root.critLevel(root.ossec ? root.ossec.maxLevel : 0)
                        }

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

                                Text {
                                    id: alertLevel

                                    width: Style.space(28)
                                    text: "L" + alertRow.modelData.level
                                    color: root.critLevel(alertRow.modelData.level)
                                    font.family: Style.font.family
                                    font.pixelSize: Style.font.caption
                                    font.bold: true
                                    layer.enabled: Style.fx.glow > 0

                                    layer.effect: Glow {
                                        shadowColor: alertLevel.color
                                    }

                                }

                                Text {
                                    width: parent.width - alertLevel.width - alertTime.width - parent.spacing * 2
                                    text: alertRow.modelData.desc
                                    elide: Text.ElideRight
                                    color: Colors.foreground
                                    opacity: Style.emphasis.strong
                                    font.family: Style.font.family
                                    font.pixelSize: Style.font.caption
                                }

                                Text {
                                    id: alertTime

                                    text: alertRow.modelData.t
                                    color: Colors.menu.text
                                    opacity: Style.emphasis.dim
                                    font.family: Style.font.family
                                    font.pixelSize: Style.font.caption
                                }

                            }

                        }

                    }

                }

                PanelSeparator {
                }

                SectionHead {
                    text: "POWER MODE"
                }

                PowerModeSelector {
                    width: parent.width
                    active: panel.visible
                }

                PanelSeparator {
                }

                SectionHead {
                    text: "TOOLS"
                }

                PanelRow {
                    width: parent.width
                    glyph: "\u{f02ca}"
                    label: "Disk speed test"
                    onActivated: {
                        if (root.bar)
                            root.bar.closePanel(root.moduleName);

                        Quickshell.execDetached(Paths.ipcCall("shell", "summon", "panel.speedtest", "{\"mode\":\"disk\"}"));
                    }
                }

            }

        }

    }

    component Stat: Row {
        id: stat
        property string glyph: ""
        property string value: ""
        property string widest: ""
        property color tint: root.bar ? root.bar.barForeground : Colors.foreground

        spacing: Style.spacing.xs

        Text {
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: parent.glyph
            color: parent.tint
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
            color: parent.tint
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.body
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

    component HudStat: Column {
        property string label: ""
        property string value: ""
        property string note: ""
        property color tint: Colors.foreground

        width: parent ? (parent.width - (parent as Grid).spacing) / 2 : 0
        spacing: Style.spacing.hair

        Text {
            text: parent.label
            color: Colors.menu.text
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            font.capitalization: Font.AllUppercase
            font.letterSpacing: Style.labelTracking
        }

        Text {
            text: parent.value
            color: parent.tint
            opacity: Style.emphasis.strong
            font.family: Style.font.family
            font.pixelSize: Style.font.title
            font.letterSpacing: Style.displayTracking
            font.features: {
                "tnum": 1
            }
        }

        Text {
            visible: parent.note.length > 0
            text: parent.note
            color: Colors.menu.text
            opacity: Style.emphasis.dim
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
        }

    }

    component FluxLabel: Item {
        property string text: ""
        property color tint: Colors.accent

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
            font.letterSpacing: Style.labelTracking
        }

    }

    component Meter: Item {
        id: meterRoot

        property string label: ""
        property real fraction: 0
        property color fill: Colors.accent
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
            color: Colors.menu.text
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            font.capitalization: Font.AllUppercase
            font.letterSpacing: Style.labelTracking
        }

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
                color: Colors.foreground
                opacity: Style.emphasis.strong
                font.family: Style.font.family
                font.pixelSize: Style.font.body
                font.letterSpacing: Style.displayTracking
                font.features: {
                    "tnum": 1
                }
            }

            Text {
                anchors.left: valPrimary.right
                anchors.leftMargin: Style.spacing.xs
                anchors.baseline: valPrimary.baseline
                visible: meterRoot.secondary.length > 0
                text: meterRoot.secondary
                color: Colors.foreground
                opacity: Style.emphasis.faint
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
                font.letterSpacing: Style.displayTracking
                font.features: {
                    "tnum": 1
                }
            }

        }

        Rectangle {
            anchors.left: meterLabel.right
            anchors.leftMargin: Style.spacing.xs
            anchors.right: meterValue.left
            anchors.rightMargin: Style.spacing.sm
            anchors.verticalCenter: parent.verticalCenter
            height: Style.space(7)
            radius: Style.shape.data
            color: Util.alpha(Colors.foreground, 0.12)

            Rectangle {
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: meterRoot.frac * parent.width
                radius: parent.radius
                color: meterRoot.fill

                Behavior on width {
                    NumberAnimation {
                        duration: Style.motion.slow
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Style.motion.enter
                    }

                }

                Behavior on color {
                    ColorAnimation {
                        duration: Style.motion.slow
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Style.motion.enter
                    }

                }

            }

        }

    }

}

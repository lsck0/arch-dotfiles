import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import qs.Commons
import qs.Ui
import "BatteryModel.js" as BatteryModel

// New widget, not a literal port. Upstream's Phase 4 "power" panel is
// mostly a battery/power-profile/system-stats display driven by 3
// omarchy-specific CLIs (omarchy-battery-status, omarchy-powerprofiles-list,
// omarchy-system-stats) that don't exist here. Rebuilt using this repo's
// own BarWidget+HoverPanel pattern (matching AudioIO.qml) instead of
// upstream's click-driven Panel base class:
//   - battery status: Quickshell.Services.UPower's own displayDevice
//     properties (percentage/state/timeToEmpty/timeToFull) directly —
//     no CLI needed, simpler than upstream's own approach. BatteryModel.js
//     keeps only the generic icon/fraction/threshold/label helpers from
//     upstream's Model.js, none of the powerprofilesctl-parsing ones.
//   - power-profile switching: toggles/toggle-powermode.sh (TLP-based,
//     already built this session) instead of power-profiles-daemon.
//   - system stats: deliberately not duplicated — System.qml already
//     covers this and TODO.md says keep it as-is, not reconciled here.
//   - no shutdown/reboot/logout/lock menu: upstream's power panel never
//     had one either (that's wlogout's job, unrelated to this widget).
BarWidget {
  id: root
  moduleName: "battery"

  readonly property var device: UPower.displayDevice
  readonly property bool present: device && device.isPresent === true
  readonly property bool onBattery: UPower.onBattery === true
  readonly property var upowerStates: ({
    Charging: UPowerDeviceState.Charging,
    Discharging: UPowerDeviceState.Discharging,
    FullyCharged: UPowerDeviceState.FullyCharged,
    PendingCharge: UPowerDeviceState.PendingCharge
  })

  readonly property real fraction: BatteryModel.batteryFraction(device)
  readonly property bool thresholdActive: BatteryModel.chargeThresholdActive(device, onBattery, upowerStates)
  readonly property string icon: BatteryModel.batteryIcon(device, onBattery, upowerStates)
  readonly property string modeLabel: BatteryModel.modeLabel(device, onBattery, upowerStates)
  readonly property string remaining: {
    if (!present) return ""
    var seconds = onBattery ? device.timeToEmpty : device.timeToFull
    return BatteryModel.formatDuration(seconds)
  }

  // Empty string means "no override" -- see toggles/toggle-powermode.sh's
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

  visible: present
  implicitWidth: present ? button.implicitWidth : 0
  implicitHeight: present ? button.implicitHeight : 0

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.icon
    tooltipText: Math.round(root.fraction * 100) + "% — " + root.modeLabel
    onEntered: root.bar.hoverOpen(root.moduleName)
    onExited: root.bar.hoverTriggerExit(root.moduleName)
  }

  HoverPanel {
    id: panel
    bar: root.bar
    moduleName: root.moduleName
    anchorWidget: root
    implicitWidth: 260
    implicitHeight: content.implicitHeight + padding * 2

    Column {
      id: content
      width: parent.width
      spacing: Style.spacing.md

      PanelSectionHeader { text: "BATTERY" }

      Row {
        width: content.width
        spacing: Style.spacing.md

        Text {
          text: root.icon
          color: root.thresholdActive ? Color.urgent : Color.menu.text
          font.pixelSize: Style.font.icon
          font.family: Style.font.family
        }

        Column {
          Text {
            text: Math.round(root.fraction * 100) + "%"
            color: Color.menu.text
            font.pixelSize: Style.font.body
            font.family: Style.font.family
            font.bold: true
          }
          Text {
            text: root.modeLabel + (root.remaining ? " · " + root.remaining : "")
            color: Qt.darker(Color.menu.text, 1.4)
            font.pixelSize: Style.font.bodySmall
            font.family: Style.font.family
          }
        }
      }

      PanelSeparator {}
      PanelSectionHeader { text: "POWER MODE" }

      Row {
        width: content.width
        spacing: Style.spacing.sm

        Repeater {
          model: ["balanced", "performance", "power-saver"]
          Rectangle {
            required property string modelData
            width: (content.width - Style.spacing.sm * 2) / 3
            height: Style.space(32)
            radius: Style.cornerRadius
            color: modelData === root.powerMode ? Color.menu.selectedBackground : "transparent"

            Text {
              anchors.centerIn: parent
              text: parent.modelData
              color: parent.modelData === root.powerMode ? Color.menu.selectedText : Color.menu.text
              font.pixelSize: Style.font.bodySmall
              font.family: Style.font.family
            }

            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: root.setPowerMode(parent.modelData)
            }
          }
        }
      }
    }
  }
}

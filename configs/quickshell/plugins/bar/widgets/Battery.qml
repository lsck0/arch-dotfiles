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
//     covers this and research/ROADMAP.md says keep it as-is, not reconciled
//     here.
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

  // Power mode lives entirely in Ui/PowerModeSelector — see its header. This
  // widget and System.qml each used to carry a full copy.
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
    // Shared panel tokens, like every other hover panel. The hardcoded 260 was
    // narrower than any other card on the bar, and omitting shadowOffset from
    // both axes clipped the card's own drop shadow away.
    implicitWidth: Style.panelWidth.narrow + Style.shadowOffset
    implicitHeight: content.implicitHeight + padding * 2 + Style.shadowOffset

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
          // iconFamily: root.icon is a Nerd Font glyph. Drawing it in the
          // user-selectable UI family is exactly the substitution Style.qml's
          // font note warns about.
          font.family: Style.font.iconFamily
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
            color: Color.menu.text
            opacity: Style.emphasis.dim
            font.pixelSize: Style.font.bodySmall
            font.family: Style.font.family
          }
        }
      }

      PanelSeparator {}
      PanelSectionHeader { text: "POWER MODE" }

      // This was a hand-rolled Repeater of Rectangles offering only the three
      // forced modes, so the default state (no override) matched no chip and
      // the group read as "nothing selected".
      PowerModeSelector {
        width: content.width
        active: panel.visible
      }
    }
  }
}

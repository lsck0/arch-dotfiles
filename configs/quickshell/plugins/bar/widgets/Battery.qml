import QtQuick
import QtQuick.Effects
import Quickshell.Services.UPower
import qs.Commons
import qs.Ui
import "BatteryModel.js" as BatteryModel

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

  // sparkline history, capped at 60
  property var chargeHist: []
  function _push(arr, v) { var a = arr.slice(); a.push(v); if (a.length > 60) a.shift(); return a }
  onFractionChanged: chargeHist = _push(chargeHist, Math.round(fraction * 100))

  visible: present
  implicitWidth: present ? button.implicitWidth : 0
  implicitHeight: present ? button.implicitHeight : 0

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.icon
    tooltipText: Math.round(root.fraction * 100) + "% — " + root.modeLabel
    onEntered: if (root.bar) root.bar.hoverOpen(root.moduleName)
    onExited: if (root.bar) root.bar.hoverTriggerExit(root.moduleName)
  }

  HoverPanel {
    id: panel
    bar: root.bar
    moduleName: root.moduleName
    anchorWidget: root
    title: "BATTERY"
    implicitWidth: Style.panelWidth.narrow + Style.shadowOffset
    implicitHeight: content.implicitHeight + padding * 2 + titleInset + Style.shadowOffset

    Column {
      id: content
      width: parent.width
      spacing: Style.spacing.md

      Row {
        width: content.width
        spacing: Style.spacing.md

        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: root.icon
          color: root.thresholdActive ? Color.urgent : Color.menu.text
          font.pixelSize: Style.font.icon
          font.family: Style.font.iconFamily
        }

        Column {
          anchors.verticalCenter: parent.verticalCenter
          Text {
            text: Math.round(root.fraction * 100) + "%"
            color: root.thresholdActive ? Color.urgent : Color.accent
            font.pixelSize: Style.font.display
            font.family: Style.font.family
            font.bold: true
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

      Column {
        width: content.width
        spacing: Style.spacing.xs
        Row {
          width: parent.width
          Text {
            width: parent.width * 0.5
            text: "CHARGE"
            color: Color.accent
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            font.bold: true
            font.capitalization: Font.AllUppercase
            font.letterSpacing: Style.headerTracking
          }
          Text {
            width: parent.width * 0.5
            horizontalAlignment: Text.AlignRight
            text: Math.round(root.fraction * 100) + "%"
            color: Color.accent
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            font.letterSpacing: Style.displayTracking
          }
        }
        Sparkline { width: parent.width; height: Style.space(34); values: root.chargeHist; minValue: 0; maxValue: 100; color: Color.accent }
        BarGauge { width: parent.width; height: Style.spacing.md; segments: 24; value: root.fraction; color: root.thresholdActive ? Color.urgent : Color.accent }
      }

      PanelSeparator {}
      PanelSectionHeader { text: "POWER MODE" }

      PowerModeSelector {
        width: content.width
        active: panel.visible
      }
    }
  }
}

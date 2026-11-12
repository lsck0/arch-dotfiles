import QtQuick
import Quickshell
import qs.Commons

Item {
  id: root

  readonly property var modeOptions: [
    { value: "auto",        label: "AUTO" },
    { value: "power-saver", label: "POWER SAVER" },
    { value: "balanced",    label: "BALANCED" },
    { value: "performance", label: "PERFORMANCE" }
  ]

  property bool active: false

  implicitWidth: group.implicitWidth
  implicitHeight: group.implicitHeight

  ToggleState {
    id: powerMode
    script: "toggle-powermode.nu"
    active: root.active
  }

  ButtonGroup {
    id: group
    width: root.width
    fill: true
    spacing: Style.spacing.xs
    options: root.modeOptions
    value: powerMode.state === "" ? "auto" : powerMode.state
    onChanged: function(value) { Quickshell.execDetached([powerMode.path, String(value)]) }
  }
}

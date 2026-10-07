import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons

// tlp power-mode chips, toggle-powermode.sh owns the state
Item {
  id: root

  readonly property var modeOptions: [
    { value: "auto",        label: "AUTO" },
    { value: "power-saver", label: "POWER SAVER" },
    { value: "balanced",    label: "BALANCED" },
    { value: "performance", label: "PERFORMANCE" }
  ]

  property bool active: false

  property color foreground: Color.menu.text
  property real fontSize: Style.font.caption

  readonly property string script: Paths.toggle("toggle-powermode.sh")

  function refresh() {
    if (!getProcess.running) getProcess.running = true
  }

  // the script announces the change over ToggleEvents, which re-reads
  function apply(mode) {
    Quickshell.execDetached([root.script, String(mode)])
  }

  onActiveChanged: if (active) refresh()
  Component.onCompleted: if (active) refresh()

  implicitWidth: group.implicitWidth
  implicitHeight: group.implicitHeight

  QtObject {
    id: internal
    property string mode: ""
  }

  Process {
    id: getProcess
    command: [root.script, "get"]
    stdout: StdioCollector {
      id: getOutput
      waitForEnd: true
    }
    onExited: internal.mode = String(getOutput.text || "").trim()
  }

  Connections {
    target: ToggleEvents
    function onChanged(script) { if (root.active && script === "toggle-powermode.sh") root.refresh() }
  }

  ButtonGroup {
    id: group
    width: root.width
    fill: true
    spacing: Style.spacing.xs
    options: root.modeOptions
    // "" means no override, shown as auto
    value: internal.mode === "" ? "auto" : internal.mode
    foreground: root.foreground
    fontSize: root.fontSize
    onChanged: function(value) { root.apply(value) }
  }
}

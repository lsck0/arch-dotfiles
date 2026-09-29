import QtQuick
import Quickshell.Io
import qs.Commons
import qs.Ui

BarWidget {
  id: root

  moduleName: "exit"

  readonly property color foreground: bar ? bar.barForeground : Color.foreground

  Process {
    id: ipcToggle
    command: Paths.ipcCall("powermenu", "toggle")
  }

  implicitWidth: button.implicitWidth
  implicitHeight: barSize

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    // fa-sign_out
    text: "\u{f08b}"
    tooltipText: "Power menu"
    foreground: root.foreground
    // WidgetButton has no clicked signal
    onPressed: ipcToggle.running = true
  }
}

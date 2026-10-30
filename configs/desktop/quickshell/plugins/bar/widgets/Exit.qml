import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "exit"
  barPriority: 40

  implicitWidth: button.implicitWidth
  implicitHeight: barSize

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "\u{f08b}"
    tooltipText: "Power menu"
    onPressed: Quickshell.execDetached(Paths.ipcCall("powermenu", "toggle"))
  }
}

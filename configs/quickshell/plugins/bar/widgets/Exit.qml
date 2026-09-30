import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "exit"

  implicitWidth: button.implicitWidth
  implicitHeight: barSize

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    // fa-sign_out
    text: "\u{f08b}"
    tooltipText: "Power menu"
    onPressed: Quickshell.execDetached(Paths.ipcCall("powermenu", "toggle"))
  }
}

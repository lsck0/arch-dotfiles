import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "app-menu"

  implicitWidth: button.implicitWidth
  implicitHeight: barSize

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    // linux-archlinux
    text: "\u{f303}"
    tooltipText: "Applications"
    onPressed: Quickshell.execDetached(Paths.ipcCall("appsearch", "toggle"))
  }
}

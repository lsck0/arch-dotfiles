import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "app-menu"
  barPriority: 55

  implicitWidth: button.implicitWidth
  implicitHeight: Style.bar.sizeHorizontal

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    hoverFill: true
    text: "\u{f303}"
    tooltipText: "Applications"
    onPressed: Quickshell.execDetached(Paths.ipcCall("appsearch", "toggle"))
  }
}

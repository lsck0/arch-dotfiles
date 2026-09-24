import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

// New widget, not from omarchy-shell (Omarchy's equivalent, omarchy.menu, is its own full menu system).
BarWidget {
  id: root
  moduleName: "app-menu"

  implicitWidth: button.implicitWidth
  implicitHeight: barSize

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    // linux-archlinux, U+F303, verified by NAME in the 0xProto Nerd Font cmap.
    text: "\u{f303}"
    tooltipText: "Applications"
    onPressed: Quickshell.execDetached(Paths.ipcCall("appsearch", "toggle"))
  }
}

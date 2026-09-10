import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

// New widget, not from omarchy-shell (Omarchy's equivalent, omarchy.menu, is
// its own full menu system). Originally launched walker, the app launcher
// used elsewhere in this repo; now toggles plugins/appsearch/AppSearch.qml,
// a purpose-built native picker over the existing AppLibrary/AppSearch.js
// services (see AppSearch.qml's own header for why the full upstream menu
// engine wasn't ported wholesale). Talks to it over IPC, same as every
// other widget-to-overlay call in this repo (see AppLibrary.qml's OSD
// calls) -- no direct property path exists from a bar widget to a
// top-level shell.qml sibling.
BarWidget {
  id: root
  moduleName: "app-menu"

  readonly property string quickshellConfigPath: Quickshell.env("HOME") + "/.config/quickshell"

  implicitWidth: button.implicitWidth
  implicitHeight: barSize

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    // linux-archlinux, U+F303, verified by NAME in the 0xProto Nerd Font
    // cmap. This was an EMPTY STRING — and BarIconButton hides itself when
    // there is no content (`hasVisualContent: text !== "" ...`), so the
    // widget was not merely icon-less, it was invisible: the SPEC's "Arch
    // icon top left which on click opens the app selector" had no way to be
    // clicked at all.
    text: "\u{f303}"
    tooltipText: "Applications"
    onPressed: Quickshell.execDetached(["quickshell", "ipc", "-p", root.quickshellConfigPath, "call", "appsearch", "toggle"])
  }
}

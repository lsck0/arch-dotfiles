import QtQuick
import Quickshell.Io
import qs.Commons
import qs.Ui

BarWidget {
  id: root

  moduleName: "bar.exit"

  readonly property color foreground: bar ? bar.barForeground : Color.foreground
  readonly property string fontFamily: bar ? bar.iconFontFamily : Style.font.iconFamily

  // Far-right bar button opening the PowerMenu (lock/exit/suspend/shutdown/
  // reboot). PowerMenu exposes IpcHandler target "powermenu" (PowerMenu.qml);
  // same call pattern as the appsearch keybind in hyprland_keybindings.lua.
  Process {
    id: ipcToggle
    command: ["quickshell", "ipc", "-p", Quickshell.env("HOME") + "/.config/quickshell", "call", "powermenu", "toggle"]
  }

  BarIconButton {
    anchors.centerIn: parent
    text: "\u{f08b}"
    foreground: root.foreground
    onClicked: ipcToggle.running = true
  }
}

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Far-right bar button opening the PowerMenu (lock/exit/suspend/shutdown/
// reboot). PowerMenu exposes IpcHandler target "powermenu" (PowerMenu.qml);
// same call pattern as the appsearch keybind in hyprland_keybindings.lua.
BarWidget {
  id: root

  // Bare name, matching every other widget ("system", "network", "media").
  // The `bar.` prefix belongs to the layout/manifest id, not to moduleName,
  // which keys the bar's shared hover-panel state.
  moduleName: "exit"

  readonly property color foreground: bar ? bar.barForeground : Color.foreground
  readonly property string fontFamily: bar ? bar.iconFontFamily : Style.font.iconFamily

  Process {
    id: ipcToggle
    command: Paths.ipcCall("powermenu", "toggle")
  }

  // Without these the widget is invisible. BarSection sizes each widget from
  // its `implicitWidth`/`implicitHeight`, and BarWidget is a bare Item that
  // has neither unless the widget states them — a centred child does not
  // give its parent a size. The button was drawing into a 0x0 box.
  implicitWidth: button.implicitWidth
  implicitHeight: barSize

  BarIconButton {
    id: button
    anchors.fill: parent
    // Required, not optional: WidgetButton reads `bar` for the icon family
    // and for its hover/tooltip wiring, and silently falls back to the
    // Style defaults when it is null.
    bar: root.bar
    // fa-sign_out, cmap-verified by name against 0xProto Nerd Font.
    text: "\u{f08b}"
    tooltipText: "Power menu"
    foreground: root.foreground
    // `pressed(int button)`, not `clicked` — WidgetButton declares no
    // clicked signal, so `onClicked` here was rejected at load time with
    // "Cannot assign to non-existent property" and the button did nothing.
    onPressed: ipcToggle.running = true
  }
}

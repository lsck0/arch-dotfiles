import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Far-right bar button opening the PowerMenu (lock/exit/suspend/shutdown/ reboot).
BarWidget {
  id: root

  // Bare name, matching every other widget ("system", "network", "media").
  moduleName: "exit"

  readonly property color foreground: bar ? bar.barForeground : Color.foreground
  readonly property string fontFamily: bar ? bar.iconFontFamily : Style.font.iconFamily

  Process {
    id: ipcToggle
    command: Paths.ipcCall("powermenu", "toggle")
  }

  // Without these the widget is invisible.
  implicitWidth: button.implicitWidth
  implicitHeight: barSize

  BarIconButton {
    id: button
    anchors.fill: parent
    // Required, not optional: WidgetButton reads `bar` for the icon family and for its hover/tooltip wiring, and silently falls back to the Style defaults when it is null.
    bar: root.bar
    // fa-sign_out, cmap-verified by name against 0xProto Nerd Font.
    text: "\u{f08b}"
    tooltipText: "Power menu"
    foreground: root.foreground
    // `pressed(int button)`, not `clicked` — WidgetButton declares no clicked signal, so `onClicked` here was rejected at load time with "Cannot assign to non-existent property" and the button did nothing.
    onPressed: ipcToggle.running = true
  }
}

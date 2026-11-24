// The settings window alone, for a session without this shell (Plasma): the "Dotfiles Settings" launcher entry runs
// `quickshell -p ~/.config/quickshell/settings-only.qml`. It opens on start and quits when closed.
import QtQuick
import Quickshell
import "plugins/settings"

ShellRoot {
  Settings {
    id: settings

    Component.onCompleted: settings.open()
    onOpenedChanged: if (!settings.opened) Qt.quit()
  }
}

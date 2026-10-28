pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
  id: root

  readonly property var commands: ["toggleSelfMute", "toggleSelfDeaf", "disconnect"]

  readonly property string runtimeDir: Quickshell.env("XDG_RUNTIME_DIR") || ""
  readonly property string commandPath: runtimeDir ? runtimeDir + "/quickshell-discord-cmd" : ""

  function send(cmd: string): bool {
    if (!root.commandPath || root.commands.indexOf(cmd) < 0) {
      console.warn("discord: rejected command", cmd)
      return false
    }
    commandFile.setText(JSON.stringify({ cmd: cmd }) + "\n")
    return true
  }

  FileView {
    id: commandFile
    path: root.commandPath
    atomicWrites: true
    printErrors: false
  }
}

pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
  id: root

  readonly property var commands: ["toggleSelfMute", "toggleSelfDeaf", "disconnect"]

  readonly property string commandPath: Paths.runtimeDir + "/quickshell-discord-cmd"

  function send(cmd: string): bool {
    if (root.commands.indexOf(cmd) < 0) {
      console.warn("discord: rejected command", cmd)
      return false
    }
    // FileView skips a setText equal to its last one, even after the plugin consumed the file: the stamp keeps each
    // command distinct
    commandFile.setText(JSON.stringify({ cmd: cmd, at: Date.now() }) + "\n")
    return true
  }

  FileView {
    id: commandFile
    path: root.commandPath
    atomicWrites: true
    printErrors: false
  }
}

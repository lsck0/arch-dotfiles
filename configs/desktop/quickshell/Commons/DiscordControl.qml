pragma Singleton
import QtQuick
import Quickshell

// channel into the QuickshellVoiceStatus betterdiscord plugin
Singleton {
  id: root

  // the plugin's _runCommand switch, anything else is dropped on this side
  readonly property var commands: ["toggleSelfMute", "toggleSelfDeaf", "disconnect"]

  readonly property string runtimeDir: Quickshell.env("XDG_RUNTIME_DIR") || ""
  readonly property string commandPath: runtimeDir ? runtimeDir + "/quickshell-discord-cmd" : ""

  // printf + mv, not FileView: the plugin unlinks the file on read and must never see a partial write
  function send(cmd: string): bool {
    if (!root.commandPath || root.commands.indexOf(cmd) < 0) {
      console.warn("discord: rejected command", cmd)
      return false
    }
    const target = Util.shellQuote(root.commandPath)
    const tmp = Util.shellQuote(root.commandPath + ".tmp")
    Quickshell.execDetached(["bash", "-c",
      "printf '%s\\n' " + Util.shellQuote(JSON.stringify({ cmd: cmd })) + " > " + tmp + " && mv -f " + tmp + " " + target])
    return true
  }
}

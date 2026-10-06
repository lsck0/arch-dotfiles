pragma Singleton
import QtQuick
import Quickshell

QtObject {
  id: root

  readonly property string home: Quickshell.env("HOME")

  readonly property string shellDir: Quickshell.shellDir

  readonly property string dotfiles: {
    var configured = String(Quickshell.env("DOTFILES") || Quickshell.env("QS_DOTFILES_DIR") || "").trim()
    var base = configured || (home + "/projects/arch-dotfiles")
    return base.replace(/\/+$/, "")
  }

  readonly property string plugins: shellDir + "/plugins"
  readonly property string barWidgets: plugins + "/bar/widgets"
  readonly property string shellScripts: shellDir + "/scripts"

  // runtime state, kept out of the tracked config dir
  readonly property string state: {
    var base = String(Quickshell.env("XDG_STATE_HOME") || "").trim() || (home + "/.local/state")
    return base.replace(/\/+$/, "") + "/quickshell"
  }

  readonly property string toggles: dotfiles + "/scripts/toggles"
  readonly property string wallpapers: dotfiles + "/wallpapers"
  readonly property string themes: dotfiles + "/configs/base/themes"

  function toggle(name) { return toggles + "/" + name }

  function barWidget(name) { return barWidgets + "/" + name }

  // name optional, then it is the plugin dir
  function plugin(pluginDir, name) {
    return plugins + "/" + pluginDir + (name ? "/" + name : "")
  }

  function script(name) { return shellScripts + "/" + name }

  function ipcCall(target, method) {
    var argv = ["quickshell", "ipc", "-p", shellDir, "call", String(target), String(method)]
    for (var i = 2; i < arguments.length; i++) {
      var arg = arguments[i]
      if (arg !== undefined && arg !== null) argv.push(String(arg))
    }
    return argv
  }
}

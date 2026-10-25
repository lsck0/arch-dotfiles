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

  readonly property string state: {
    var base = String(Quickshell.env("XDG_STATE_HOME") || "").trim() || (home + "/.local/state")
    return base.replace(/\/+$/, "") + "/quickshell"
  }

  readonly property string runtime: {
    return String(Quickshell.env("XDG_RUNTIME_DIR") || "").trim().replace(/\/+$/, "") + "/quickshell"
  }

  readonly property string toggles: dotfiles + "/scripts/toggles"
  readonly property string wallpaperList: dotfiles + "/configs/core/wallust/wallpaper-list.nu"
  readonly property string themes: dotfiles + "/themes"

  function toggle(name) { return toggles + "/" + name }

  function barWidget(name) { return barWidgets + "/" + name }

  function plugin(pluginDir, name) {
    return plugins + "/" + pluginDir + (name ? "/" + name : "")
  }

  function script(name) { return shellScripts + "/" + name }

  function ipcCall(target, method) {
    var argv = ["quickshell", "ipc", "-p", shellDir, "call", String(target), String(method)]
    for (let i = 2; i < arguments.length; i++) {
      let arg = arguments[i]
      if (arg !== undefined && arg !== null) argv.push(String(arg))
    }
    return argv
  }
}

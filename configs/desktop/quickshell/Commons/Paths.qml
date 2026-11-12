pragma Singleton
import QtQuick
import Quickshell

QtObject {
  readonly property string home: Quickshell.env("HOME")

  readonly property string shellDir: Quickshell.shellDir

  readonly property string dotfiles: envDir("DOTFILES", home + "/projects/arch-dotfiles")
  readonly property string state: envDir("XDG_STATE_HOME", home + "/.local/state") + "/quickshell"
  readonly property string wal: envDir("XDG_CACHE_HOME", home + "/.cache") + "/wal"
  // the bare runtime dir holds files shared with the nu helpers (quickshell-pomodoro, toggles/, ...)
  readonly property string runtimeDir: envDir("XDG_RUNTIME_DIR", "/tmp")
  readonly property string runtime: runtimeDir + "/quickshell"

  readonly property string notes: home + "/sync/notes/notes.md"

  readonly property string wallpaperList: dotfiles + "/configs/core/wallust/wallpaper-list.nu"
  readonly property string themes: dotfiles + "/themes"

  function envDir(name, fallback) {
    return (String(Quickshell.env(name) || "").trim() || fallback).replace(/\/+$/, "")
  }

  function toggle(name) { return dotfiles + "/scripts/toggles/" + name }

  function plugin(name) { return shellDir + "/plugins/" + name }

  function barWidget(name) { return plugin("bar/widgets/" + name) }

  function script(name) { return shellDir + "/scripts/" + name }

  // a command the dotfiles link into ~/.local/bin (dot, task-calendar, ...)
  function bin(name) { return home + "/.local/bin/" + name }

  function ipcCall(target, method) {
    var argv = ["quickshell", "ipc", "-p", shellDir, "call", String(target), String(method)]
    for (let i = 2; i < arguments.length; i++) {
      let arg = arguments[i]
      if (arg !== undefined && arg !== null) argv.push(String(arg))
    }
    return argv
  }
}

pragma Singleton
import QtQuick
import Quickshell

// Every filesystem path the shell reaches outside its own QML tree.
QtObject {
  id: root

  readonly property string home: Quickshell.env("HOME")

  // ~/.config/quickshell.
  readonly property string shellDir: Quickshell.shellDir

  // Override with QS_DOTFILES_DIR for a checkout that is not at the default location.
  readonly property string dotfiles: {
    var configured = String(Quickshell.env("QS_DOTFILES_DIR") || "").trim()
    var base = configured || (home + "/projects/arch-dotfiles")
    return base.replace(/\/+$/, "")
  }

  // ---- inside the shell ------------------------------------------------

  readonly property string plugins: shellDir + "/plugins"
  readonly property string barWidgets: plugins + "/bar/widgets"
  // Shell-owned helper scripts.
  readonly property string shellScripts: shellDir + "/scripts"

  // ---- outside the shell, in the checkout ------------------------------

  // The only place a persistent state change may be written from — see ROADMAP ground rule #1.
  readonly property string toggles: dotfiles + "/toggles"
  readonly property string repoScripts: dotfiles + "/scripts"
  readonly property string wallpapers: dotfiles + "/wallpapers"
  readonly property string themes: dotfiles + "/themes"

  // ---- joins ----------------------------------------------------------- Named after the root they resolve against, so a call site reads as a claim about where the file lives rather than as string concatenation.

  // `Paths.toggle("toggle-dnd.sh")`
  function toggle(name) { return toggles + "/" + name }

  // `Paths.barWidget("system-stats.sh")`
  function barWidget(name) { return barWidgets + "/" + name }

  // `Paths.plugin("clipboard", "capture.sh")` — the second argument is optional, so it also names a plugin's own directory.
  function plugin(pluginDir, name) {
    return plugins + "/" + pluginDir + (name ? "/" + name : "")
  }

  // `Paths.repoScript("switch-wallpaper.sh")`
  function repoScript(name) { return repoScripts + "/" + name }

  // `Paths.bin("pomodoro")` — a shell helper as link.sh exposes it in ~/.local/bin, without its .sh suffix.
  function bin(name) { return home + "/.local/bin/" + name }

  // Argv for an `ipc call` against this shell instance.
  function ipcCall(target, method) {
    var argv = ["quickshell", "ipc", "-p", shellDir, "call", String(target), String(method)]
    for (var i = 2; i < arguments.length; i++) {
      var arg = arguments[i]
      if (arg !== undefined && arg !== null) argv.push(String(arg))
    }
    return argv
  }
}

pragma Singleton
import QtQuick
import Quickshell

// Every filesystem path the shell reaches outside its own QML tree.
//
// Before this existed, 23 call sites across 17 files each spelled out
// `Quickshell.env("HOME") + "/projects/arch-dotfiles/..."`. That hardcodes
// both the checkout location *and* the internal layout of the repo into
// widget code: moving the checkout, or moving a helper script one directory
// sideways, silently broke a scattered subset of widgets, each failing as a
// Process that exits non-zero with nobody watching.
//
// Two roots, and the distinction matters:
//
//   shellDir  — `Quickshell.shellDir`, i.e. ~/.config/quickshell, whose
//               entries link.sh symlinks into this checkout. Anything that
//               ships *inside* the shell (widget helper scripts, plugin
//               assets, theme.json) must be addressed from here. It needs no
//               configuration and follows the checkout wherever it goes.
//   dotfiles  — the repo root, needed only for things that live outside
//               configs/quickshell: toggles/*.sh (the state-change contract
//               from ROADMAP ground rule #1), repo-level scripts/, and the
//               wallpaper/theme asset directories. There is no way to derive
//               this from shellDir, because link.sh links the *contents* of
//               configs/quickshell rather than the directory itself, so
//               walking up from shellDir lands in ~/.config. Hence one env
//               override with the conventional location as the default.
QtObject {
  id: root

  readonly property string home: Quickshell.env("HOME")

  // ~/.config/quickshell. Also the right `-p` argument for `quickshell ipc`
  // calls the shell makes against itself.
  readonly property string shellDir: Quickshell.shellDir

  // Override with QS_DOTFILES_DIR for a checkout that is not at the default
  // location. Trailing slashes are trimmed so joins below never double up.
  readonly property string dotfiles: {
    var configured = String(Quickshell.env("QS_DOTFILES_DIR") || "").trim()
    var base = configured || (home + "/projects/arch-dotfiles")
    return base.replace(/\/+$/, "")
  }

  // ---- inside the shell ------------------------------------------------

  readonly property string plugins: shellDir + "/plugins"
  readonly property string barWidgets: plugins + "/bar/widgets"
  // Shell-owned helper scripts. link.sh also exposes these on PATH under
  // ~/.local/bin without their .sh suffix; addressing them by full path here
  // keeps the shell working regardless of what PATH a session happens to
  // have.
  readonly property string shellScripts: shellDir + "/scripts"

  // ---- outside the shell, in the checkout ------------------------------

  // The only place a persistent state change may be written from — see
  // ROADMAP ground rule #1.
  readonly property string toggles: dotfiles + "/toggles"
  readonly property string repoScripts: dotfiles + "/scripts"
  readonly property string wallpapers: dotfiles + "/wallpapers"
  readonly property string themes: dotfiles + "/themes"

  // ---- joins -----------------------------------------------------------
  //
  // Named after the root they resolve against, so a call site reads as a
  // claim about where the file lives rather than as string concatenation.

  // `Paths.toggle("toggle-dnd.sh")`
  function toggle(name) { return toggles + "/" + name }

  // `Paths.barWidget("system-stats.sh")`
  function barWidget(name) { return barWidgets + "/" + name }

  // `Paths.plugin("clipboard", "capture.sh")` — the second argument is
  // optional, so it also names a plugin's own directory.
  function plugin(pluginDir, name) {
    return plugins + "/" + pluginDir + (name ? "/" + name : "")
  }

  // `Paths.repoScript("switch-wallpaper.sh")`
  function repoScript(name) { return repoScripts + "/" + name }

  // `Paths.bin("pomodoro")` — a shell helper as link.sh exposes it in
  // ~/.local/bin, without its .sh suffix. Addressed by full path rather than
  // by name so it does not depend on the session's PATH.
  function bin(name) { return home + "/.local/bin/" + name }

  // Argv for an `ipc call` against this shell instance. The `-p` argument is
  // the one thing every such call gets wrong when written by hand.
  function ipcCall(target, method, arg) {
    var argv = ["quickshell", "ipc", "-p", shellDir, "call", String(target), String(method)]
    if (arg !== undefined && arg !== null) argv.push(String(arg))
    return argv
  }
}

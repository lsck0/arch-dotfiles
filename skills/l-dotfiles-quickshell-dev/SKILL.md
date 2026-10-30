---
name: l-dotfiles-quickshell-dev
description: Editing the quickshell shell (bar, launcher, lock, notifications, OSD) in configs/desktop/quickshell, live reload, logs, IPC calls and screenshots of its layers. Load when changing or debugging the bar or any shell UI.
---

# quickshell-dev

`configs/desktop/quickshell/mod.nu` copies the tree (`theme.json` included) into `~/.config/quickshell`; an edit lands
with `dot apply desktop/quickshell`, and a live edit is drift. Runs as `quickshell.service` (started by
`hyprland_autostart.lua`). Entry `shell.qml`; `plugins/<name>/`, `Commons/` singletons, `scripts/` helpers.

## Edit loop

1. `dot apply desktop/quickshell`; the shell reloads (`Configuration Loaded` in the log), not while the lock is held.
2. `journalctl --user -u quickshell -f -o cat` names file and line of a QML error.
3. Still broken or crashed: `~/.config/quickshell/restart.nu` (restarts the unit, kills strays, bakes shaders).

## IPC

```bash
qs ipc -p ~/.config/quickshell show                  # every target and function
qs ipc -p ~/.config/quickshell call bar toggle <panel>
qs ipc -p ~/.config/quickshell call bar list         # panel names
```

The bar target is `bar` on the main screen and `bar-<output>` elsewhere. `bar open|toggle` (mod+b then a letter) gives
the panel the keyboard: hjkl/arrows move, Tab jumps sections, Esc or q closes. An `IpcHandler { target: "<name>" }`
adds a target; keybinds call them through `quickshell_call(target, fn)` in `hyprland_keybindings.lua`.

`~/.config/quickshell` is the user's live shell: an agent only reads it (`show`, `list`). A `call` that opens or
toggles drives the user's screen; check UI on a test shell in the nested Hyprland instead
(`XDG_RUNTIME_DIR=$rt WAYLAND_DISPLAY=wayland-<n> qs ipc -p <copy> call ...`, `l-dotfiles-gui-testing`).

## Screenshot one layer

```bash
g=$(hyprctl layers -j | jq -r '[.[] | .levels[][] | select(.namespace == "quickshell-bar")][0] | "\(.x),\(.y) \(.w)x\(.h)"')
grim -g "$g" /tmp/bar.png
```

Geometry is logical, the PNG physical (scale 1.67 on the desktop). Verification screenshots go on the agent's own
headless output (`l-dotfiles-gui-testing`).

## Pitfalls

- Never start a second quickshell in the user's session: it takes over notifications, and a test lock locks the real
  screen. Test the lock only in `dbus-run-session` around a nested compositor.
- A test shell runs on a private short `XDG_RUNTIME_DIR` (`l-dotfiles-gui-testing`): `Lock.qml` keeps its
  crash-recovery marker in `$XDG_RUNTIME_DIR/quickshell/locked`, so a locked test shell killed on the real one locks the
  user's shell on its next start. Every helper it started outlives it: teardown in `l-dotfiles-gui-testing`.
- Hot reload sometimes misses: no fresh `Configuration Loaded` means `restart.nu`.
- Helper processes keep old code (cava, pomodoro until a shell restart; `obs-status.nu` until OBS restarts).
- Never `pkill -f`: the pattern matches the agent's own shell. Kill by PID.

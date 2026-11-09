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
3. No fresh `Configuration Loaded`, still broken or crashed: `~/.config/quickshell/restart.nu` (restarts the unit,
   kills strays, bakes shaders; Luca's `SUPER+SHIFT+r`). The restart flickers his live bar: while he works, ask.

Launcher capture (`+` task, `!` reminder, `#` note) runs `scripts/capture.nu`; `appsearch openWith '<text>'` opens the
launcher on a mode (`SUPER+i`). The desktop agenda (`plugins/desktop`) groups now, all day, meetings and to do; its
quote sits on the wallpaper with theme-independent colours (`Colors.wallpaperText`).

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

Reading the live bar's own layer is fine; anything that launches or opens UI goes to `l-dotfiles-gui-testing`.

```bash
g=$(hyprctl layers -j | jq -r '[.[] | .levels[][] | select(.namespace == "quickshell-bar")][0] | "\(.x),\(.y) \(.w)x\(.h)"')
grim -g "$g" /tmp/bar.png
```

Geometry is logical, the PNG physical (scale 1.67 on the desktop). Verification screenshots go on the agent's own
headless output (`l-dotfiles-gui-testing`).

## Pitfalls

- Never start a second quickshell in the user's session: it takes over notifications, and a test lock locks the real
  screen. A test shell runs only in the nested `dbus-run-session` Hyprland on a private `XDG_RUNTIME_DIR`, and its
  helpers outlive it: start, lock marker and teardown in `l-dotfiles-gui-testing`.
- Hot reload sometimes misses: no fresh `Configuration Loaded` means `restart.nu`. It always fails with "<Name> is not
  a type" for an inline component (`component X: ...`) or a file new to the running process; a fresh process loads the
  same tree, so after adding one, restart.
- Check new non-window types before restarting the live bar: a copy of the tree with a test `shell.qml` wrapping them in
  `Component {}`, run with `QT_QPA_PLATFORM=offscreen`, a private `XDG_RUNTIME_DIR` and `dbus-run-session` in a
  `systemd-run --user` unit with `-p OnFailure=` (the failure notifier stays quiet). Window types fail there with "No
  PanelWindow backend loaded".
- Hover panels stay compact: a reading appears once per panel (no hero, row, sparkline and gauge for one metric),
  empty sections and one-point sparklines hide, long lists cap with an expand row, about 1000 logical px a panel.
- Helper processes keep old code (cava, pomodoro until a shell restart; `obs-status.nu` until OBS restarts).

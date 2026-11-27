---
name: l-dotfiles-quickshell-dev
description: "Editing the quickshell shell in configs/desktop/quickshell (bar, panels, launcher, lock, notifications, OSD): apply and reload loop, logs, qs ipc targets, layer screenshots, offscreen QML harnesses. Load when changing or debugging any shell UI. Driving the live shell for Luca: l-dotfiles-desktop-control; a test shell: l-dotfiles-gui-testing."
---

# quickshell-dev

Layout, UI copy rules, launcher prefixes, reminders and IPC summons: `configs/desktop/quickshell/AGENTS.md`.
`mod.nu` copies the tree (`config/`) into `~/.config/quickshell`, so a live edit there is drift. Runs as
`quickshell.service`. `Ui/GlassCard.qml` is the one card material, `Ui/Scrim.qml` the dim behind every overlay.

## Edit loop

1. `dot apply desktop/quickshell`; the shell hot-reloads (`Configuration Loaded` in the log), not while the lock is
   held.
2. `journalctl --user -u quickshell -f -o cat` names file and line of a QML error. Fix, back to 1.
3. No fresh `Configuration Loaded`, still broken or crashed: `~/.config/quickshell/restart.nu` (restarts the unit, kills
   strays, bakes shaders; Luca's `SUPER+SHIFT+r`). It flickers his live bar: while he works, ask.

## IPC

```bash
qs ipc -p ~/.config/quickshell show                  # every target and function
qs ipc -p ~/.config/quickshell call bar list         # panel names
qs ipc -p ~/.config/quickshell call bar toggle <panel>
```

- The bar target is `bar` on the main screen and `bar-<output>` elsewhere (`open|close|toggle|state|list`). An opened
  panel takes the keyboard (Luca: `mod+b` then a letter): hjkl/arrows move, Tab jumps sections, Esc or q closes.
- An `IpcHandler { target: "<name>" }` adds a target; keybinds reach it through `quickshell_call(target, fn)` in
  `configs/desktop/hyprland/config/hyprland_keybindings.lua`.
- On the live shell an agent only reads (`show`, `list`, `state`) unless Luca asked; a `call` that opens or toggles
  drives his screen. Check UI on a test shell (`l-dotfiles-gui-testing`).

## Screenshot the bar

Reading the live bar's own layer is fine; anything that opens UI goes to `l-dotfiles-gui-testing`.

```bash
g=$(hyprctl layers -j | jq -r '[.[] | .levels[][] | select(.namespace == "quickshell-bar")][0] | "\(.x),\(.y) \(.w)x\(.h)"')
grim -g "$g" /tmp/bar.png
```

Geometry is logical, the PNG physical (scale 1.67 on luca-pc).

## Test new types without the live bar

- Non-window types: a copy of the tree with a test `shell.qml` wrapping them in `Component {}`, run with
  `QT_QPA_PLATFORM=offscreen`, a private `XDG_RUNTIME_DIR` and `dbus-run-session` in a `systemd-run --user` unit with
  `-p OnFailure=` (keeps the failure notifier quiet). Window types fail there with "No PanelWindow backend loaded".
- A scripted harness: copy `plugins/bar/widgets/media.test.nu` (offscreen shell copy, stubbed PanelWindows, fake D-Bus
  services on a private bus, an `IpcHandler` the test drives).

## Pitfalls

- Never start a second quickshell in Luca's session: it takes over notifications, and a test lock locks the real
  screen. A test shell runs only in the nested Hyprland (`l-dotfiles-gui-testing`).
- Hot reload always fails with "<Name> is not a type" for an inline component (`component X: ...`) or a file new to the
  running process: after adding one, `restart.nu`.
- A `.pragma library` script (`Schema.js`, `Palette.js`, `Plugins.js`, the `*Model.js`) is imported once: hot reload
  keeps its old code. `dot apply desktop/quickshell` restarts the unit when one changes, so ask Luca before applying
  such an edit to his live shell.
- Helper processes keep old code: cava and `pomodoro.nu` until a shell restart, `obs-status.nu` until OBS restarts.
- Hover panels stay compact: a reading appears once per panel (no hero, row, sparkline and gauge for one metric),
  empty sections and one-point sparklines hide, long lists cap with an expand row, about 1000 logical px a panel.

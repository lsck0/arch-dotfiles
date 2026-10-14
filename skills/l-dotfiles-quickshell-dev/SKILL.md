---
name: l-dotfiles-quickshell-dev
description: Editing the quickshell shell (bar, launcher, lock, notifications, OSD) in configs/desktop/quickshell, live reload, logs, IPC calls and screenshots of its layers. Load when changing or debugging the bar or any shell UI.
---

# quickshell-dev

`configs/desktop/quickshell/mod.nu` copies the checkout into `~/.config/quickshell` (`theme.json` stays a link), so
an edit reaches the running shell with `dot link desktop/quickshell`. Entry `shell.qml`; plugins under
`plugins/<name>/`, shared singletons in `Commons/` (`Colors`, `Style`, `Paths`, `ToggleEvents`), helper scripts in
`scripts/` (linked as commands). It runs as `quickshell.service`
(user unit, started by `hyprland_autostart.lua`, not enabled).

## Edit loop

1. Save the `.qml` and run `dot link desktop/quickshell`: quickshell watches its copies and reloads
   (`Reloading configuration...` then `Configuration Loaded` in the log); not while the session lock is held,
   `shell.qml` turns the watch off then.
2. Logs:
   ```bash
   journalctl --user -u quickshell -f -o cat
   ```
   A QML error names file and line there. A reload that leaves it broken or a crash:
   `~/.config/quickshell/restart.nu` (resets the start limit and restarts the unit; also kills strays and bakes
   `shaders/*.frag` to `.qsb`).

## IPC

```bash
qs ipc -p ~/.config/quickshell show                          # every target and function
qs ipc -p ~/.config/quickshell call notifications isDnd
qs ipc -p ~/.config/quickshell call bar toggle <panel>
```

An `IpcHandler { target: "<name>" }` in any QML file adds a target. Keybinds call these from
`configs/desktop/hyprland/hyprland_keybindings.lua` (`quickshell_call(target, fn)`).

## Screenshot one layer

```bash
hyprctl layers -j | jq -r '.[] | .levels[][] | .namespace' | sort -u
g=$(hyprctl layers -j | jq -r '[.[] | .levels[][] | select(.namespace == "quickshell-bar")][0] | "\(.x),\(.y) \(.w)x\(.h)"')
grim -g "$g" /tmp/bar.png
```

Layer geometry is logical; the PNG is in physical pixels (scale 1.67 on the desktop). Read the image to check the
change. A panel opened over IPC first (`call bar open <panel>`) shows up as its own layer.

When an agent screenshots only to verify a change (not because the user is watching the bar), do it on a headless
output the user never sees rather than the physical monitors: `hyprctl output create headless` gives a `HEADLESS-N`
that the running shell puts a bar on, `grim -o HEADLESS-N`, then `hyprctl output remove HEADLESS-N`. Each agent
makes and removes its own, so several can check at once without taking over the screen (AGENTS.md gotchas).

Never start a second quickshell in the user's session: it competes for `org.freedesktop.Notifications`, and a
session lock is compositor-wide, so a test lock locks the real screen. Test the lock only fully isolated:
`dbus-run-session` around a nested compositor (`Hyprland` or `weston --backend=headless`) with `WAYLAND_DISPLAY` and
`HYPRLAND_INSTANCE_SIGNATURE` pointing at it.

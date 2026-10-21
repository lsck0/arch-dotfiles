---
name: l-dotfiles-quickshell-dev
description: Editing the quickshell shell (bar, launcher, lock, notifications, OSD) in configs/desktop/quickshell, live reload, logs, IPC calls and screenshots of its layers. Load when changing or debugging the bar or any shell UI.
---

# quickshell-dev

`configs/desktop/quickshell/mod.nu` copies the checkout into `~/.config/quickshell` (`theme.json` stays a link), so
an edit reaches the running shell with `dot apply desktop/quickshell`. Entry `shell.qml`; plugins under
`plugins/<name>/`, shared singletons in `Commons/` (`Colors`, `Style`, `Paths`, `ToggleEvents`), helper scripts in
`scripts/` (linked as commands). It runs as `quickshell.service`
(user unit, started by `hyprland_autostart.lua`, not enabled).

## Edit loop

1. Save the `.qml` and run `dot apply desktop/quickshell`: quickshell watches its copies and reloads
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
qs ipc -p ~/.config/quickshell call bar list                 # panel names (each HoverPanel's moduleName)
```

`bar open|toggle` is the keyboard path (mod+b then a letter, the `panels` submap): the panel stays open, takes the
keyboard (`WlrKeyboardFocus.Exclusive`) and focuses its first control; hjkl/arrows walk the controls, Tab jumps
per `PanelSectionHeader`, Esc or q closes. Hover opens after 140 ms; a click on the bar item pins the panel.

Targets (`show` lists the live ones with signatures):

| target | functions |
|---|---|
| `shell` | `palette`, `reloadPowerMode`, `summon <id> <json>` |
| `bar`, `bar-<output>` | `open <panel>`, `close`, `toggle <panel>`, `state`, `list` |
| `settings` | `toggle`, `open`, `close`, `openOn <output>` |
| `appsearch`, `powermenu`, `tasks` | `toggle`, `open`, `close` |
| `clipboard` | `toggle`, `open`, `close`, `forget <hash>` |
| `overview` | `toggle`, `open`, `close`, `next`, `prev`, `commit` |
| `notifications` | `dndState`, `toggleDnd`, `setDnd <value>`, `isDnd`, `showHistory`, `clear`, `dismissAll`, `dismissOne`, `invokeLast`, `dismiss <summary>`, `ping` |
| `osd` | `present <json>`, `close`, `state`, `ping` |
| `lock` | `lock`, `isLocked` |
| `background` | `refresh`, `set <path>`, `setInstant <path>` |
| `discord` | `toggleMute`, `toggleDeafen`, `disconnect` |
| `obs` | `toggleListen`, `listen <bool>`, `listening` |
| `toggles` | `changed <script>` (`scripts/toggles/lib.nu` after a flip) |

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

A screenshot only to verify a change goes on the agent's own headless output, which the running shell puts a bar on
(skill `l-dotfiles-gui-testing`).

Never start a second quickshell in the user's session: it competes for `org.freedesktop.Notifications`, and a
session lock is compositor-wide, so a test lock locks the real screen. Test the lock only fully isolated:
`dbus-run-session` around a nested compositor (`Hyprland` or `weston --backend=headless`) with `WAYLAND_DISPLAY` and
`HYPRLAND_INSTANCE_SIGNATURE` pointing at it.

## Pitfalls

- `~/.config/quickshell` is copies: an edit in the repo does nothing until `dot apply desktop/quickshell`.
- Hot reload sometimes misses: check `journalctl --user -u quickshell` for a fresh `Configuration Loaded`, else run
  `configs/desktop/quickshell/restart.nu`.
- Widget helper processes keep their old code: cava and pomodoro until the shell restarts; `obs-status.nu` runs only
  while OBS runs, so restart the shell or OBS. The obs keybinds run the repo's `obs-status.nu` directly.
- Never `pkill -f`: the pattern matches the agent's own shell. Kill by PID.
- The bar's IPC target is `bar` on the main screen (else the first) and `bar-<output>` on the others (`plugins/bar/Bar.qml`).

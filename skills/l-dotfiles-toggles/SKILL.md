---
name: l-dotfiles-toggles
description: Adding an on/off or n-state switch as scripts/toggles/toggle-<name>.nu with lib.nu, its root half, and wiring it into quickshell and the menu. Load when adding or changing a toggle.
---

# toggles

Every `scripts/toggles/toggle-*.nu` answers `get` (the state alone) and `get --json`, its status record from
`status-record` in `lib.nu`: `{name, label, state, text, states, on, available}`, `states` every value with the
resting one first (`[off on]` for a switch, empty for an open setting like the font), `on` whether it is away from
rest, `available` whether this machine offers it. An on/off one also answers `on | off | toggle` through `switch-run`
(its switch record may carry an `available` closure); an n-state one (route, firewall, powermode, shader,
color-grading, font, monitor-scale) has its states as a const record and `set <value>` plus `toggle` (most cycle with
`cycle-next`; shader switches between off and the last shader, monitor-scale steps up and wraps, route skips offline). Patterns worth copying:
`toggle-focus.nu` (on/off over other toggles through `toggle-run`, restoring their states), `toggle-weather-location.nu`
(on/off plus `set <lat> <lon>`, `clear` and query verbs), `toggle-theme-mode.nu` (two states without `switch-run`:
its own `get`, `set light|dark`, `light`, `dark`, `toggle`), `toggle-obs-listen.nu` (an app's live state over its
websocket), `toggle-route.nu` (exclusive states over several tools: direct, protonvpn, the tor router, offline).
`status.nu [name...]` lists the records of every toggle or the named ones (plus `options` with `--options`), `menu.nu`
on `SUPER+t` shows the available ones in `configs/desktop/hyprland/picker.nu` (`--fzf` in a terminal). A new script appears in both without
registration. `get` stays cheap and side-effect free: `dot set` and the settings window read it.
A script that also answers `options` (JSON rows shaped like `dot set --json`, each with the `set` verb that
writes it, see `toggle-font.nu`) shows those rows in the settings window instead of its step row, through
`status.nu --options`; a long `choices` list there is a filterable pick list.

## Add one

1. `scripts/toggles/toggle-<name>.nu`, executable:
   ```nu
   #!/usr/bin/env -S nu --no-config-file
   use lib.nu [switch-run]

   def main [action: string = "toggle", --json] {
       switch-run {
           label: "<Label>"
           is-on: {|| ... }      # bool, no side effects
           on: {|| ... }
           off: {|| ... }
           available: {|| ... }  # optional, bool
       } $action --json=$json
   }
   ```
   Shortcuts: `switch-run (service-switch <label> <unit>) $action --json=$json` for a systemd unit, `radio-switch <label>
   wifi|wwan`. State without a live probe: `state-get`/`state-set`/`state-clear` (`~/.local/state/toggles`), with
   `--volatile` (tmpfs) for state that resets on boot. Another toggle: `toggle-run <name> <action>`.
2. Root work goes through one `root-run <verb> ...` per flip (one password prompt at most), which runs `/usr/local/bin/toggle-root` (from
   `configs/core/toggles/toggle-root.nu`) via pkexec for wheel users only; add the verb there and the polkit rule in
   `configs/core/toggles/49-toggles.rules` if needed. Anything that lowers a guard uses `systemctl-guarded`.
3. `switch-run` calls `notify`, which pings quickshell (`toggles changed <script>`) and sends a notification; an
   n-state toggle calls `notify` itself after a change. Nothing polls.

## Quickshell wiring (only for a dedicated control)

- Run it: `Quickshell.execDetached([Paths.toggle("toggle-<name>.nu"), "toggle"])`.
- Refresh on change: connect to `ToggleEvents.changed(script)` and compare `script === "toggle-<name>.nu"`
  (see `plugins/bar/indicators/StayAwake.qml`).

## Test

```bash
scripts/toggles/toggle-<name>.nu get
scripts/toggles/toggle-<name>.nu get --json   # the status record
scripts/toggles/toggle-<name>.nu toggle; scripts/toggles/toggle-<name>.nu toggle
scripts/toggles/status.nu | jq '.[] | select(.name == "<name>")'
nu --no-config-file --ide-check 50 scripts/toggles/toggle-<name>.nu
dot test lint
```

---
name: l-dotfiles-toggles
description: Adding an on/off or n-state switch as scripts/toggles/toggle-<name>.nu with lib.nu, its root half, and wiring it into quickshell and the menu. Load when adding or changing a toggle.
---

# toggles

Every `scripts/toggles/toggle-*.nu` answers `get` and `label`; an on/off one also `on | off | toggle` through
`switch-run` in `lib.nu`, an n-state one (firewall, powermode, shader, color-grading, font, monitor-scale) has its
states as a const record and `set <value>` plus `toggle` (cycles with `cycle-next`). Patterns worth copying:
`toggle-focus.nu` (on/off over other toggles through `toggle-run`, restoring their states), `toggle-weather-location.nu`
(on/off plus `set <lat> <lon>`, `clear` and query verbs), `toggle-theme-mode.nu` (two states without `switch-run`:
its own `get`, `set light|dark`, `light`, `dark`, `toggle`), `toggle-obs-listen.nu` (an app's live state over its
websocket). `status.nu` runs every `label`
(JSON `{name, on, setting, label}`), `menu.nu` is the picker on `SUPER+t`. A new script appears in both without
registration. `get` stays cheap and side-effect free: `dot set` and the settings window read it.
A script that also answers `options` (JSON rows shaped like `dot set --json`, each with the `set` verb that
writes it, see `toggle-font.nu`) shows those rows in the settings window instead of its step row, through
`status.nu --options`; a long `choices` list there is a filterable pick list.

## Add one

1. `scripts/toggles/toggle-<name>.nu`, executable:
   ```nu
   #!/usr/bin/env -S nu --no-config-file
   use lib.nu [switch-run]

   def main [action: string = "toggle"] {
       switch-run {
           label: "<Label>"
           is-on: {|| ... }      # bool, no side effects
           on: {|| ... }
           off: {|| ... }
       } $action
   }
   ```
   Shortcuts: `switch-run (service-switch <label> <unit>) $action` for a systemd unit, `radio-switch <label>
   wifi|wwan`. State without a live probe: `state-get`/`state-set`/`state-clear` (`~/.local/state/toggles`), with
   `--volatile` (tmpfs) for state that resets on boot. Another toggle: `toggle-run <name> <action>`.
2. Root work goes through `root-run <verb> ...`, which runs `/usr/local/bin/toggle-root` (from
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
scripts/toggles/toggle-<name>.nu label        # the label with its on/off marker
scripts/toggles/toggle-<name>.nu toggle; scripts/toggles/toggle-<name>.nu toggle
scripts/toggles/status.nu | jq '.[] | select(.name == "<name>")'
nu --no-config-file --ide-check 50 scripts/toggles/toggle-<name>.nu
dot test lint
```

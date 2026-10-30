---
name: l-dotfiles-toggles
description: Adding an on/off or n-state switch as scripts/toggles/toggle-<name>.nu with lib.nu, its root half, and wiring it into quickshell and the menu. Load when adding or changing a toggle.
---

# toggles

Every `scripts/toggles/toggle-*.nu` answers `get` (the state) and `get --json` (the record from `status-record` in
`lib.nu`: `{name, label, state, text, states, on, available}`; `states` lists the resting state first). On/off ones go
through `switch-run` (`on|off|toggle`); n-state ones take `set <value>` and `toggle` (`cycle-next`): route, firewall
and powermode keep their states in a const record, color-grading cycles the presets `color-grading.py` reports, font
sets any installed family and cycles its shortlist; shader toggles between off and the last shader, monitor-scale
steps through its own `SCALES` list. `status.nu [name...]` lists the records, `menu.nu` (`prefix+m` in tmux and
herdr) shows them; a new script appears in both without registration. `get` stays cheap and side-effect free: `dot
set` and the settings window call it. A script answering `options` (rows shaped like `dot set --json`, see
`toggle-font.nu`) shows those rows in the settings window instead.

Examples: `toggle-focus.nu` (combines toggles via `toggle-run`), `toggle-theme-mode.nu` (own `get`/`set`),
`toggle-obs-listen.nu` (live app state), `toggle-route.nu` (exclusive states over several tools).

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
           available: {|| ... }  # optional
       } $action --json=$json
   }
   ```
   Shortcuts: `service-switch <label> <unit>`, `radio-switch <label> wifi|wwan`; state without a probe:
   `state-get`/`state-set`/`state-clear` (`--volatile` resets on boot).
2. Root work: one `root-run <verb>` per flip (one prompt at most), running `toggle-root`
   (`configs/core/toggles/toggle-root.nu`) via pkexec; add the verb there and a rule in `49-toggles.rules` if needed.
   Lowering a guard uses `systemctl-guarded`.
3. `switch-run` notifies quickshell (`toggles changed <script>`); an n-state toggle calls `notify` itself.

Quickshell control (only for a dedicated one): run `Quickshell.execDetached([Paths.toggle("toggle-<name>.nu"),
"toggle"])`, refresh on `ToggleEvents.changed(script)`.

## Test

```bash
scripts/toggles/toggle-<name>.nu get --json
scripts/toggles/toggle-<name>.nu toggle; scripts/toggles/toggle-<name>.nu toggle
nu --no-config-file --ide-check 50 scripts/toggles/toggle-<name>.nu
dot test lint
```

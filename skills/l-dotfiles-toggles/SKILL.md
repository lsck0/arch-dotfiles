---
name: l-dotfiles-toggles
description: Adding an on/off or n-state switch as scripts/toggles/toggle-<name>.nu with lib.nu, its root half, and wiring it into quickshell and the menu. Load when adding or changing a toggle. Flipping one for Luca is l-dotfiles-desktop-control.
---

# toggles

Every `scripts/toggles/toggle-*.nu` answers `get` (the state) and `get --json` (the record from `status-record` in
`lib.nu`: `{name, label, state, text, states, on, available}`; `states` lists the resting state first). On/off ones go
through `switch-run` (`on|off|toggle`); n-state ones take `set <value>` and `toggle` (`cycle-next`): route, firewall
and powermode keep their states in a const record and switch under `exclusive-run`, color-grading cycles the presets
`color-grading.py` reports, font sets any installed family and cycles its shortlist; shader toggles between off and
the last shader, monitor-scale steps through its own `SCALES` list. `status.nu [name...]` lists the records,
`menu.nu` (`prefix+m` in tmux and herdr) shows them; a new script appears in both without registration. `get` stays
cheap and side-effect free: `dot set` and the settings window call it. A script answering `options` (rows shaped like
`dot set --json`, see `toggle-font.nu`) shows those rows in the settings window instead.

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
   Shortcuts: `service-switch <label> <unit> [socket...]` (sockets that would start the unit again stop and start
   with it), `radio-switch <label> wifi|wwan`; state without a probe: `state-get`/`state-set`/`state-clear`
   (`--volatile` resets on boot; state a reboot must keep goes without it). A toggle whose effect resets on reboot
   while its state persists answers `reapply`, as `toggle-focus.nu` does, run at session start by
   `configs/core/toggles/toggles-reapply.service`.
2. Root work: one `root-run <verb>` per flip (`root-run tor-start`) (one prompt at most), running `toggle-root`
   (`configs/core/toggles/toggle-root.nu`) via pkexec. The helper takes no flags and `49-toggles.rules` allowlists
   whole command lines, so a new verb goes into both: `VERBS_UNPROMPTED` (`tor-start`) when it tightens or guards
   nothing, `VERBS_LOWERING` when it lowers a guard (asked, then the helper's `approval-record` stamp lets the next lowering
   pass for 5 minutes, `APPROVAL_MINUTES` in `mod.nu`).
3. `switch-run` notifies quickshell (`toggles changed <script>`); an n-state toggle calls `notify` itself and runs its
   switch through `exclusive-run <label> _apply <state>` (the script again under its lock). Either runs one flip at
   a time (a press meanwhile says "Still switching"); `switch-run` skips an `on`/`off` already in that state and
   takes `{said: <body>}` from on/off in place of "Turned on". A failure is the one critical toast of `notify-failed
   <label> <cause> --to <state> --now <state>` ("Switch to X failed, now Y: <cause>"): `switch-run` sends it with the
   closure's `err.msg`, an n-state `_apply` calls it itself; `root-run` and `service-switch` raise the last stderr
   line as that cause. `TOGGLES_QUIET=1` (a combined toggle's parts) keeps the ping and failures, not the success
   toast.

Quickshell control (only for a dedicated one): run `Quickshell.execDetached([Paths.toggle("toggle-<name>.nu"),
"toggle"])`, refresh on `ToggleEvents.changed(script)`.

## Test

```bash
scripts/toggles/toggle-<name>.nu get --json
scripts/toggles/toggle-<name>.nu toggle; scripts/toggles/toggle-<name>.nu toggle
nu --no-config-file --ide-check 50 scripts/toggles/toggle-<name>.nu
dot test lint
```

`scripts/toggles/toggles.test.nu` walks the state machines of the network, focus and power toggles against stubs in a
bwrap sandbox (no real bus, network or unit flips) and runs in `dot test lint`; a new state or transition gets a step
there.

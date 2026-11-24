---
name: l-dotfiles-toggles
description: "Adding or changing a switch in scripts/toggles/toggle-<name>.nu: lib.nu (switch-run, service-switch, exclusive-run), its root half in toggle-root and 49-toggles.rules, quickshell and menu wiring, toggles.test.nu. Load when adding or changing a toggle. Flipping one for Luca: l-dotfiles-desktop-control."
---

# toggles

Every `scripts/toggles/toggle-*.nu` answers `get` and `get --json` (`status-record` in `lib.nu`:
`{name, label, state, text, states, on, available}`, `states` with the resting state first). `status.nu [name...]`
lists the records and `menu.nu` (`prefix+m` in tmux and herdr) shows them: a new script appears in both without
registration. `get` stays cheap and side-effect free: `dot set` and the settings window call it. A script answering
`options` (rows shaped like `dot set --json`, `toggle-font.nu`) shows those rows in the settings window instead.

Kinds, with the file to copy:

- on/off through `switch-run` (`on|off|toggle`): `toggle-dnd.nu`; combining others via `toggle-run`: `toggle-focus.nu`;
  live app state: `toggle-obs-listen.nu`.
- n-state with `set <value>` and `toggle` (`cycle-next`), states in a const record, switched under `exclusive-run`:
  `toggle-route.nu`, `toggle-firewall.nu`, `toggle-powermode.nu`; own `get`/`set`: `toggle-theme-mode.nu`.

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
   Shortcuts: `service-switch <label> <unit> [socket...]` (sockets that would restart the unit stop and start with
   it), `radio-switch <label> wifi|wwan`. State without a probe: `state-get`/`state-set`/`state-clear`; `--volatile`
   resets on boot. An effect that resets on reboot while its state persists: answer `reapply` (`toggle-focus.nu`),
   which `configs/core/toggles/config/toggles-reapply.service` runs at session start.
2. Root work: one `root-run <verb>` per flip (one prompt at most), running
   `configs/core/toggles/scripts/toggle-root.nu` via pkexec. The helper takes no flags and `49-toggles.rules`
   allowlists whole command lines, so a new verb goes into both: `VERBS_UNPROMPTED` when it tightens or guards
   nothing, `VERBS_LOWERING` when it lowers a guard (asked once, then `approval-record` lets the next lowering pass
   for `APPROVAL_MINUTES` in `mod.nu`).
3. Notifications come from `lib.nu`; keep them consistent:
   - `switch-run` pings quickshell (`toggles changed <script>`), runs one flip at a time ("Still switching"), skips an
     `on`/`off` already in that state, and takes `{said: <body>}` from on/off in place of "Turned on".
   - An n-state toggle calls `notify` itself and runs its switch as `exclusive-run <label> _apply <state>`.
   - A failure is one critical toast, `notify-failed <label> <cause> --to <state> --now <state>`: `switch-run` sends it
     with the closure's `err.msg`, an n-state `_apply` itself; `root-run` and `service-switch` raise the last stderr
     line as the cause.
   - `TOGGLES_QUIET=1` (a combined toggle's parts) keeps the ping and failures, drops the success toast.
4. A dedicated quickshell control only: `Quickshell.execDetached([Paths.toggle("toggle-<name>.nu"), "toggle"])`,
   refreshed on `ToggleEvents.changed(script)`.

## Test

```bash
scripts/toggles/toggle-<name>.nu get --json
scripts/toggles/toggle-<name>.nu toggle; scripts/toggles/toggle-<name>.nu toggle
nu --no-config-file --ide-check 50 scripts/toggles/toggle-<name>.nu
dot test lint
```

Flipping a real toggle changes Luca's live machine: a security-weighted one (route, vpn, firewall, trust-network,
portal, anonymous-socks) only after his yes. `scripts/toggles/toggles.test.nu` walks the network, focus and power state
machines against stubs in a bwrap sandbox and runs in `dot test lint`; a new state or transition gets a step there.

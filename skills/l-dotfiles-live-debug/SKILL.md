---
name: l-dotfiles-live-debug
description: Reading the live system dot manages: dot status, run logs and traces, FAILURES files, the crash record, user journals and failed units, files changed since their apply, which module wrote a file, AppArmor denials, quickshell logs, restarting a user service. Load when something on the machine misbehaves or a dot run failed.
---

# live-debug

Everything here only reads, except the restart at the end.

## dot

```bash
dot status --brief        # failed checks only
dot status [--json]       # generation, last run, pending work, managed files changed since their apply, every check
dot log [--module <id>] [--level WARN]   # the last changing run's records
dot log <run> --trace     # span tree with timings
dot plan [mod...]         # what an apply would do, drift included
dot explain <path|pkg>    # which module, verb and run wrote it, or declares the package
dot module adopt <file>   # a hand edit becomes the module's source
dot module reset <file>   # back to the module's copy, the edit preserved aside
```

- `FAILURES.config` / `FAILURES.install` at the repo root: the last run's failures, system included; `config.log` /
  `install.log` the terminal output.
- A crashed run leaves `~/.local/state/dotfiles/crash.json`. Root's state: `/var/lib/dotfiles`.
- Exit 3 under `DOT_SYSTEM=skip` is a pending system part, not a failure.

## systemd, AppArmor, quickshell

```bash
systemctl --user --failed
journalctl --user -u <unit> -b --no-pager | tail -50
journalctl -b -p warning --no-pager | tail -50
journalctl -k -b --no-pager -g 'apparmor="DENIED"' | tail     # fix: l-dotfiles-apparmor-profile
journalctl --user -u quickshell -o cat                        # the running shell
```

Each quickshell instance also logs to `/run/user/$UID/quickshell/by-id/<id>/log.log` (newest dir is live); reload and
IPC: `l-dotfiles-quickshell-dev`.

## Is Hyprland even running

A keybind, `hyprctl` call or bar that does nothing may mean the session is Plasma: `ly` remembers the last session.

```bash
loginctl show-session "$XDG_SESSION_ID" -p Desktop -p Type   # Desktop=KDE: plain Plasma
pgrep -x Hyprland                                             # empty: not running
```

`hypridle.service` can show active as a leftover under KWin; it proves nothing.

## Homelab

A homelab service that times out: `l-homelab`, section Debugging.

## Everything at once

`collect-diagnostics [dest]` writes `dest/diag-<host>-<time>/`: hardware, boot, network, DNS, firewall, journals (this
boot, previous, last five as zstd exports), failed units, `dot status`, `dot log`, `FAILURES*`, run logs, crash record,
stage state, Hyprland and quickshell logs. Bash and coreutils only, so it runs from a USB stick. Asks sudo once for the
root parts, skips them without. `dest` defaults to `$PWD`, from the stick to the script's dir.

## Restart

`systemctl --user restart <unit>` (after `reset-failed` if it hit its start limit); quickshell via
`configs/desktop/quickshell/restart.nu`. Never restart an app the user is working in without asking.

---
name: l-dotfiles-live-debug
description: Reading the live system dot manages: dot status, run logs and traces, FAILURES files, the crash record, user journals and failed units, drift, which module wrote a file, AppArmor denials, quickshell logs, restarting a user service. Load when something on the machine misbehaves or a dot run failed.
---

# live-debug

Read first, change nothing: every command here only reads, except the restart at the end.

## dot

```bash
dot status --brief        # failed checks only, "<check>: <text>"
dot status                # generation, last run and errors, pending migrations / system parts / applies, managed files
                          # changed since their apply, every check, then each machine's drift report (state/drift)
dot status --json         # the same as one record
dot log                   # the last changing run's records (read-only runs like status/plan skipped), INFO and up;
                          # --module <id>, --level WARN
dot log <run> --trace     # the span tree with timings; run ids complete
dot plan [mod...]         # what an apply would do, drift included; touches nothing
dot explain <path|pkg>    # which module, verb and run wrote a path, or which module declares a package
```

- `FAILURES.config` / `FAILURES.install` at the repo root: what failed in the last run, system failures included;
  `config.log` / `install.log` the terminal output.
- `~/.local/state/dotfiles/crash.json`: the record a crashed run leaves. Root's state is `/var/lib/dotfiles`.
- Exit 3 from a `DOT_SYSTEM=skip` run is a pending system part, not a failure.
- Another machine's drift: `configs/secrets/state/drift/<host>` (plaintext); `dot internal drift report` gives this
  machine's.

## systemd

```bash
systemctl --user --failed
journalctl --user -u <unit> -b --no-pager | tail -50
journalctl -b -p warning --no-pager | tail -50
```

## AppArmor

```bash
journalctl -k -b --no-pager -g 'apparmor="DENIED"' | tail
```

The fix is skill `l-dotfiles-apparmor-profile`.

## quickshell

`journalctl --user -u quickshell -o cat` is the running shell. Each instance also logs under
`/run/user/$UID/quickshell/by-id/<id>/log.log`; the newest dir (`ls -t`) is the live one. Skill
`l-dotfiles-quickshell-dev` covers reload and IPC.

## Everything at once

`collect-diagnostics [dest]` (`scripts/collect-diagnostics.sh`) gathers one folder, `dest/diag-<host>-<time>/`:
hardware, boot, network, DNS and firewall, this boot's journals (warnings, kernel, AppArmor, the previous boot), the
last five boots as zstd journal exports, every failed unit's status and journal, `dot status` and `dot log`,
`FAILURES*`, the run logs, the crash record and the install stage state, Hyprland's and quickshell's logs. Bash and
coreutils only: it runs from a USB stick on any Linux, where nushell, dot or the network do not. It asks sudo once up
front for the root parts (nft, sbctl, root-only files) and skips them without it. `dest` defaults to `$PWD` for the
linked command, else the script's own dir (the stick).

## Restart

A user service restarts with `systemctl --user restart <unit>`, after `systemctl --user reset-failed <unit>` when
it hit its start limit. Quickshell restarts through `configs/desktop/quickshell/restart.nu`. Never restart an app
the user is working in without asking.

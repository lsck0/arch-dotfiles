---
name: l-dotfiles-live-debug
description: Reading the live system dot manages: dot status, run logs and traces, FAILURES files, the crash record, user journals and failed units, drift, which module wrote a file, AppArmor denials, quickshell logs, restarting a user service. Load when something on the machine misbehaves or a dot run failed.
---

# live-debug

Read first, change nothing: every command here only reads, except the restart at the end.

## dot

```bash
dot status --brief        # failed checks only, "<check>: <text>"
dot status                # generation, pending migrations and system parts, drift, every check
dot status --json         # the same as one record
dot log                   # the last run's records, INFO and up; --module <id>, --level WARN
dot log <run> --trace     # the span tree with timings; run ids complete
dot plan [mod...]         # what an apply would do, drift included; touches nothing
dot explain <path|pkg>    # which module, verb and run wrote a path, or which module declares a package
```

- `FAILURES.config` / `FAILURES.install` at the repo root: what failed in the last run, system failures included;
  `config.log` / `install.log` the terminal output.
- `~/.local/state/dotfiles/crash.json`: the record a crashed run leaves. Root's state is `/var/lib/dotfiles`.
- Exit 3 from a `DOT_SYSTEM=skip` run is a pending system part, not a failure.

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

## Restart

A user service restarts with `systemctl --user restart <unit>`, after `systemctl --user reset-failed <unit>` when
it hit its start limit. Quickshell restarts through `configs/desktop/quickshell/restart.nu`. Never restart an app
the user is working in without asking.

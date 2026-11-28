---
name: l-dotfiles-live-debug
description: "Reading the live system dot manages: dot status, dot log, FAILURES files, crash.json, a silent hung run, journals and failed units, drift, who wrote a file, AppArmor denials, core dumps, stuck packages, collect-diagnostics. Load when something on the machine misbehaves or a dot run failed or hangs. A stopped install chain or its banner: l-dotfiles-install."
---

# live-debug

Everything here only reads, except `dot module adopt|reset` and a user service restart. Never answer a prompt a run is
waiting on, and never restart an app Luca is working in without asking.

## Triage

1. `dot status --brief`: FAIL and todo checks only. `dot status [--json]` adds generation, last run, pending work,
   drift and every check, ordered `FAIL`, `todo`, `note`, `ok` (`LEVELS` in `scripts/lib/doctor.nu`). `todo` is
   pending work, no fault, but `--brief`, `--json` and the exit code count it as `FAIL`; `--json` marks it
   `pending: true`, and core/alloy's metrics split the two (`dot_check_failed`, `dot_check_pending`).
2. `FAILURES.config` / `FAILURES.install` at the repo root: the last run's failures, system included, one line each as
   `<module> <verb>/<step>: <cause>; fix: <hint>`. Fixes come from `HINTS` in `scripts/lib/cause.nu`; a new failure
   class is a row there.
3. `dot log [run] [--module <id>] [--level WARN]`: the last changing run's records, root's runs
   (`/var/lib/dotfiles/runs`) merged in. `dot log <run> --trace`: span tree with timings and each span's errors.
4. `config.log` / `install.log` / `sync.log` in the checkout hold the output of the last run at a terminal; an agent's
   run writes none, so use `dot log`.

```bash
dot plan [mod...]         # what an apply would do, drift included
dot explain <path|pkg>    # which module, verb and run wrote it, or declares the package
dot module adopt <file>   # a hand edit becomes the module's source
dot module reset <file>   # back to the module's copy, the edit preserved aside
```

## Reading the signs

- Exit 3 is pending, not failed: a system part under `DOT_SYSTEM=skip` or after a dismissed pkexec prompt, or modules
  waiting on packages (`dot apply --packages` installs them).
- Alive but silent: the run may sit on a question on `/dev/tty` that no log shows (`ledger: remove ...? [y/N]`, or
  pacman's `[Y/n]`). `ps -ef --forest` shows a `bash -c ... confirm <question>` in its `read`, or pacman, under the
  run. Tell Luca.
- `crash` (note): a crashed run left `$XDG_STATE_HOME/dotfiles/crash.json` (root's: `/var/lib/dotfiles`), its `cause`
  the same as the PANIC line in `dot log`. The command's next run that goes through removes it.
- `stuck` (note): a package installed above its repo's version; `-Su` never replaces it. The fix,
  `sudo pacman -S <name>`, is Luca's.
- `cores` (note): programs that dumped core in the last 24 h; `coredumpctl info <exe>` for the backtrace.
- Slow run: `dot log <run> --trace` times each phase. Any lib edit re-evaluates every module once (eval dominates);
  that is expected. In engine code, closure-taking commands (`each`, `where`, `items`, `reduce`) in per-module loops
  cost in proportion to everything the process parsed, which is why `dot plan|apply|status` exec the small
  `scripts/lib/pipeline-cli.nu`.

## systemd, AppArmor, quickshell

```bash
systemctl --user --failed
journalctl --user -u <unit> -b --no-pager | tail -50
journalctl -b -p warning --no-pager | tail -50
journalctl -k -b --no-pager -g 'apparmor="DENIED"' | tail     # fix: l-dotfiles-apparmor-profile
journalctl --user -u quickshell -o cat                        # the shell; reload and IPC: l-dotfiles-quickshell-dev
```

Every quickshell instance, a test or nested one too, also logs to `/run/user/$UID/quickshell/by-id/<id>/log.log`
(newest dir is live); the journal sees only the unit.

A keybind, `hyprctl` call or bar that does nothing may mean the session is Plasma (`ly` remembers the last session):
`loginctl show-session "$XDG_SESSION_ID" -p Desktop -p Type` says `Desktop=KDE`, `pgrep -x Hyprland` is empty.
`hypridle.service` can show active as a leftover under KWin; it proves nothing.

A homelab service that times out: `l-homelab`, section When it does not answer; a lab-side fault: `l-homelab-debug`.

## Everything at once

`collect-diagnostics [--root <mnt>] [dest]` writes `dest/diag-<host>-<time>/`: hardware, boot, network, firewall,
journals, failed units, `dot status`, `dot log`, `FAILURES*`, run logs, crash record, stage state, Hyprland and
quickshell logs. Bash only, so it runs from the install stick; `--root` reads an installed system mounted there (LUKS
opened, `@`, `@home`, `@log` mounted as its fstab does). Root parts need sudo, so they are Luca's run.

## Restart

`systemctl --user restart <unit>` (after `systemctl --user reset-failed <unit>` if it hit its start limit), for a unit
Luca is not working in. quickshell or an open app only after he agrees, via `~/.config/quickshell/restart.nu`.

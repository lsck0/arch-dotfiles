---
name: l-dotfiles-live-debug
description: "Reading the live system dot manages: dot status, run logs and traces, FAILURES files, the crash record, user journals and failed units, files changed since their apply, which module wrote a file, AppArmor denials, quickshell logs, restarting a user service. Load when something on the machine misbehaves or a dot run failed, hangs or says nothing. A stopped install chain or its login banner is l-dotfiles-install."
---

# live-debug

Everything here only reads, except `dot module adopt|reset` and the restart at the end.

## dot

```bash
dot status --brief        # FAIL and todo checks only
dot status [--json]       # generation, last run, pending work, managed files changed since their apply, every check
dot log [--module <id>] [--level WARN]   # the last changing run's records
dot log <run> --trace     # span tree with timings
dot plan [mod...]         # what an apply would do, drift included
dot explain <path|pkg>    # which module, verb and run wrote it, or declares the package
dot module adopt <file>   # a hand edit becomes the module's source
dot module reset <file>   # back to the module's copy, the edit preserved aside
```

- `dot status` lists each check under its level, `FAIL`, `todo` (pending work, no fault: an apply, `--packages` or a
  reboot due), `note`, `ok`, in that order (`LEVELS` in `scripts/lib/doctor.nu`). `--brief`, `--json` and the exit
  code count `todo` as `FAIL`; `--json` reports it as `FAIL`.
- `FAILURES.config` / `FAILURES.install` at the repo root: the last run's failures, system included, one line each as
  `<module> <verb>/<step>: <cause>; fix: <hint>` (the command, its exit code or `not installed (<package>)`, the last
  stderr lines, the file:line); `dot status` groups them by cause. The fixes come from `HINTS` in
  `scripts/lib/cause.nu`; a new failure class is a row there.
- `config.log` / `install.log` / `sync.log` in the checkout: the output of the last `dot apply`, `dot apply
  --packages` and `dot sync` that ran at a terminal, teed there (no pty of its own). A run without one (an agent's)
  writes none: `dot log`.
- A run that is alive but silent may sit on a question asked on `/dev/tty`, which no log shows: undeclared packages
  (`ledger: remove ...? [y/N]`) or pacman's own `[Y/n]`. `ps -ef --forest` shows a `bash -c ... confirm <question>`
  in its `read`, or pacman, under the run: tell Luca, never answer it.
- A crashed run leaves `$XDG_STATE_HOME/dotfiles/crash.json`, its `cause` the same record as the PANIC line's in
  `dot log`; `dot log --trace` shows each span's errors under it. The command's next run that goes through removes
  it; until then `dot status` notes it (`crash`). Root's state: `/var/lib/dotfiles`; each root entry writes a run file
  under `runs/` there, which `dot log` merges into the run that asked for it. `dot log` with no run recorded prints a
  note. Cut-off state (the ledger's last line, a module's record, a run log line, the discover
  cache) is dropped or rescanned, a warning where it matters, never a crash.
- Login banners in `/etc/issue.d/` (`dotfiles-stage`, `-config`, `-secrets`): `l-dotfiles-install`, Check the chain.
- Exit 3 means pending, not a failure: a system part under `DOT_SYSTEM=skip` or after a dismissed pkexec prompt, or
  modules waiting on their packages (`dot status` lists them; `dot apply --packages` installs them).
- A slow run: `dot log <run> --trace` times each phase (discover, detect, resolve, graph, state, imports, versions,
  inputs, observe, eval, packages). Any lib edit re-evaluates every module once (eval dominates); that is expected.
  Engine code keeps closure-taking commands (`each`, `where`, `items`, `reduce`) out of per-module loops: each call
  costs in proportion to the commands the process parsed, which is why `dot plan|apply|status` exec the small
  `scripts/lib/pipeline-cli.nu`.

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

`collect-diagnostics [--root <mnt>] [dest]` writes `dest/diag-<host>-<time>/`: hardware, boot, network, DNS,
firewall, journals (this boot, previous, last five as zstd exports), failed units, `dot status`, `dot log`,
`FAILURES*`, run logs, crash record, stage state, Hyprland and quickshell logs. Bash and coreutils only, so it runs from
a USB stick. `--root` also reads an installed system mounted there from the stick (its LUKS root opened, `@`, `@home`
and `@log` mounted as its fstab does): its journal, dot state, stage and install logs, boot config. Root parts go
through sudo (Luca's run; without sudo they are skipped). `dest` defaults to a mounted `LSCK0` partition (the install
stick's, which carries the script too), else `$XDG_STATE_HOME/diagnostics` (never the checkout), from elsewhere the
script's dir. The raw-written iso leaves its EFI partition (answer files) nearly full; `LSCK0` is a FAT32 partition
added behind it in the free space.

## Restart

`systemctl --user restart <unit>` (after `reset-failed` if it hit its start limit); quickshell via
`configs/desktop/quickshell/restart.nu`. Never restart an app the user is working in without asking.

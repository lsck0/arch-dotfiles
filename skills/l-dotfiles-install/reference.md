# install reference

## lsck0 iso stub

- Waits for internet (archlinux.org and github answering; cable, else the answer file's `wifi` or a picker; never
  offline), clones master, checks HEAD against the iso's signing key and runs that `bootstrap.sh` with
  `LSCK0_INSTALL=1`.
- Frozen on the stick: the stub up to its newer-stub switch (network, clone, signature check) and the trust anchor from
  `bootstrap.sh`. Everything else comes from master at install time; only a change to the frozen part needs a reburn.
  A newer verified stub on master replaces the stick's.
- The lab mirror is probed apart: on an outage the bootstrap drops `[lsck0]` from the live `pacman.conf`
  (`pacman-conf-lsck0`) and installs without it; a platform with the `homelab` fact stops before the disk is touched
  (re-checked at pacstrap).
- `efibootmgr --bootnext` points at the new ESP before the reboot; each stage reboot sets BootNext to its own entry.

## Answer files

- `lsck0.nuon` or `lsck0.<name>.nuon` on a FAT32 partition labelled `LSCK0` (and other places); keys in
  `mirror/iso/lsck0.example.nuon`. `lsck0.*` boot parameters map to `BOOTSTRAP_*`. An answered key is not asked.
- One file found: a 10 s yes/no, then it is used. Several: a menu plus "no answer file", which takes the first after
  10 s only when it is the one file saying `unattended: true`. A file that does not parse is listed as ignored. Only
  the pick's `source` files are staged; a missing one stops the install. The second stage does not search again.
- `unattended: true` skips the summary, asks each `"ask"` password once up front under the install's keymap, logs to
  `/tmp/lsck0-install.log` (copied to `/var/log/lsck0-install.log`).
- Unattended, a disk whose ESP holds `/boot/dotfiles-stage-in-progress` is refused unless `reinstall: true`
  (`BOOTSTRAP_REINSTALL=1`, or the one-boot `lsck0.reinstall=1`): a running chain is left to finish, a stopped one is
  named with its resume.
- The answer file's `source` (an unverified tree over master, the vm test's) is used only with `lsck0.insecure=1`, in a
  VM, or after a yes on the console.

## Questions

`scripts/lib/bootstrap/questions.nuon`, in ask order (id = answer-file key, kind, title, text, options, default,
`BOOTSTRAP_*` env, `when`; code steps are entries with `step`). Top-level `answers` holds answer-file-only keys,
`messages` and `summary` every other text. Wording, order or a new question is an edit there; `bootstrap.nu` only walks
the list. Prompts stay short: one question, the options, at most one line of context for a risky choice.

- Order: keyboard, profile, machine, home network (`server` and `custom` add theirs here), disk, encryption (LUKS2,
  default yes), login name, passwords, summary.
- Profile: `profiles/<name>.nuon` (luca) or `custom` (default, no capabilities); copied to
  `~/.config/dotfiles/profile.nuon`.
- Machine: `server` (not on WSL), `custom`, then each `platforms/<name>.nuon` by `label` (WSL: only `wsl`; `vm`
  hidden). A named pick goes to `/etc/dotfiles/platform`. `server` and `custom` ask hostname, an ssh key (empty:
  console only), off WSL timezone, locale and secure boot (`own`, `microsoft` default, `off`), and write
  `/etc/dotfiles/platform.nuon` and `.options.nuon`. `server` is base plus docker; `custom` asks the groups.

## Unattended variables

No tty or `BOOTSTRAP_ASSUME_YES=1`: answers from env. `BOOTSTRAP_{USERNAME,DISK,PASSWORD,USER_PASSWORD,ROOT_PASSWORD,
KEYMAP}` (keymap default de-latin1; `BOOTSTRAP_KEYMAP_DEFAULT` only preselects; no username default),
`BOOTSTRAP_PROFILE` (default custom), `BOOTSTRAP_PLATFORM=<name>|server|custom` (default custom; the `bootstrap.sh`
argument wins), `BOOTSTRAP_HOME_NETWORK=0|1`, `BOOTSTRAP_ENCRYPT=0|1` (default 1); server or custom also
`BOOTSTRAP_{HOSTNAME,GROUPS,TIMEZONE,LOCALE,SSH_KEY,SECURE_BOOT}`. `BOOTSTRAP_SERVER=1` turns custom into server. Each
question's `env` and `default` in `questions.nuon` is the reference.

## WSL

Keyring, upgrade, wheel user, `wsl.conf` (systemd, default user, hostname, no Windows PATH), verified repo,
`~/.local/bin/dot` and a minimal `~/.zshenv`/`~/.zshrc` (the first apply takes both over). Machine `wsl`: groups base,
core, programming, no homelab; firewall, vpn and tor modules off; hardware modules skip themselves, so sudo is
password only. No YubiKey without USB passthrough: `dot secrets unlock --identity <age file>`.

Luca's test on Windows: `wsl --install archlinux`, the `bootstrap.sh` one-liner from
`raw.githubusercontent.com/lsck0/arch-dotfiles/master/bootstrap.sh` piped to bash, `wsl --terminate archlinux`, then
`systemctl is-system-running` (running or degraded), `dot sync --no-push`, `dot status --brief`.

## When a sync enters root

Due (`system-due` in `scripts/lib/run.nu`): a failed or pending check, work in the system plan, undeclared packages,
pending migrations, changed system secrets, an edit to `/etc/dotfiles/platform*` since the last clean entry
(`platform-edited`), else a package upgrade.

Not due: a root copy that differs only in files root never acts on (`root-acts-on` in `scripts/lib/system.nu`),
packages and modules waiting only on the mirror's next build (until checkupdates lists an awaited package,
`awaited-arrived`), and a module with `meta.secrets` undoing outputs. The user side skips a module whose input and root
record match `~/.local/state/dotfiles/system-inputs.nuon`, saved after a clean root entry. A non-wheel login converges
its user layer only.

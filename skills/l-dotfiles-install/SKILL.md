---
name: l-dotfiles-install
description: Installing a machine from this repo (owner, generic, WSL), how the unattended boot chain runs, and adding another login on an installed machine. Load when setting up or reinstalling a machine or user.
---

# install

Three stages: `bootstrap.sh` (nushell, a verified checkout, then `dot internal bootstrap`: keyboard, disk, base system,
user, root copy, arms the chain), then `dot internal stage` runs `dot apply --packages` and `dot apply` on their own
boots, unattended, and retires itself and its sudo drop-in at the end, or stops disarmed (Check the chain).

## Install

1. Arch Linux-LSCK0 iso, https://mirror.lsck0.dev/iso/archlinux-lsck0-latest-x86_64.iso (check `.sha256`, and `.sig`
   against `configs/base/pacman/archrepo.asc`, signer `HOMELAB.mirror.isoSigner` in `platforms/homelab.nu`,
   `88042EFBF5F141C2ACF4697ADD84D7C4053DD354`; `dot test run` checks both), written raw to a stick. Its stub autologins on tty1, waits for internet (cable, else the answer file's `wifi` or a
   picker; never offline), clones master, checks HEAD against the iso's signing key and runs that `bootstrap.sh` with
   `LSCK0_INSTALL=1`, which starts `dot internal iso-install` (`scripts/lib/iso-install.nu`).
   - Answer file: `lsck0.nuon` or `lsck0.<name>.nuon` on a FAT32 partition labelled `LSCK0` (and other places), keys
     in `mirror/iso/lsck0.example.nuon`; `lsck0.*` boot parameters map to `BOOTSTRAP_*`. An answered key is not asked.
   - One answer file found: a 10 s yes/no, then it is used (an unattended boot goes on by itself); several: a menu of
     them plus "no answer file", which takes the first after 10 s only when that one says `unattended: true`. Each
     file is found once (by path and content); one that does not parse is listed as ignored, never offered. Only the
     pick's `source` files are staged, into a dir of its own; a missing one stops the install. No answer file means
     every question is asked; the second stage does not search again, and a picked file it cannot parse stops it.
     An older stub connects with the first `lsck0.nuon`'s wifi, then switches to master's stub, which asks.
   - `unattended: true` skips the summary, asks each `"ask"` password once up front, logs to `/tmp/lsck0-install.log`
     (copied to `/var/log/lsck0-install.log`).
   - Unattended, a disk whose ESP holds `/boot/dotfiles-stage-in-progress` (a chain still running) is refused unless
     `reinstall: true` (`BOOTSTRAP_REINSTALL=1`, or the one-boot `lsck0.reinstall=1`).
   - `efibootmgr --bootnext` points at the new ESP before the reboot; each stage reboot sets BootNext to its own entry.
   - The answer file's `source` (an unverified tree over master, the vm test's) is used only with `lsck0.insecure=1`,
     in a VM, or after a yes on the console.
   - Frozen on the stick: the stub up to its newer-stub switch (network, clone, signature check) and the trust anchor
     from `bootstrap.sh`. Everything else comes from master at install time; only a change to the frozen part needs a
     reburn. A newer verified stub on master replaces the stick's.
2. From the official Arch ISO: `curl -fsSL https://install-linux.lsck0.dev | sh`.

Build the iso: `dot internal iso` (root, mkarchiso).

- `bootstrap.sh` (bash, runs only on the Arch ISO or WSL) installs nushell (grows the overlay if needed), clones master
  and refuses unless HEAD is signed by `SIGNING_KEY_FINGERPRINT` (`BOOTSTRAP_INSECURE=1` skips). From an existing
  checkout it skips the clone.
- Questions: `scripts/lib/bootstrap/questions.nuon`, in ask order (id = answer-file key, kind, title, text, options,
  default, `BOOTSTRAP_*` env, `when`; code steps are entries with `step`). Top-level `answers` holds answer-file-only
  keys; `messages` and `summary` every other text. The iso's second stage reads its keys and types from it. Wording,
  order or a new question is an edit there; `bootstrap.nu` only walks the list.
- Order: keyboard, profile, machine, home network (`server` and `custom` add their questions here), then disk,
  encryption, login name, passwords, summary. Nothing is written before the summary's `install`.
- Login name, profile and machine are independent; nothing derives from the login name.
- Profile: `profiles/<name>.nuon` (luca) or `custom` (default, no file, no capabilities); copied to
  `~/.config/dotfiles/profile.nuon`.
- Machine: `server` (not on WSL), `custom`, then each `platforms/<name>.nuon` by `label` (WSL: only `wsl`; `vm` hidden,
  the vm test names it). A named pick goes to `/etc/dotfiles/platform`. `server` and `custom` ask hostname, an ssh key
  for `~/.ssh/authorized_keys` (empty: console only), off WSL timezone, locale and secure boot (`own`, `microsoft`
  default, `off`), and write `/etc/dotfiles/platform.nuon` (and `.options.nuon`). `server` is base plus docker;
  `custom` asks the groups.
- Every machine asks for disk encryption (LUKS2, default yes).
- Prompts stay short: one question, the options, at most one line of context for a risky choice.

## WSL

The same line in a fresh Arch distro's root shell. No disk, bootloader or chain: keyring, upgrade, wheel user,
`wsl.conf` (systemd, default user, hostname, no Windows PATH), verified repo, `~/.local/bin/dot` and a minimal
`~/.zshenv`/`~/.zshrc` (the first apply takes both over). Machine `wsl`: groups base, core, programming, no homelab;
firewall, vpn and tor modules off. Hardware modules skip themselves, so sudo is password only; `core/locale` sets
`en_US.UTF-8`. No YubiKey without USB passthrough: `dot secrets unlock --identity <age file>` (fetches the submodule
via `gh auth` or the ssh key).

Test on Windows (WSL 2.x):

1. `wsl --update`, `wsl --install archlinux`.
2. `curl -fsSL https://raw.githubusercontent.com/lsck0/arch-dotfiles/master/bootstrap.sh | bash`; machine `wsl`,
   profile `custom` or `luca`, user, password.
3. `wsl --terminate archlinux`, `wsl -d archlinux`; `systemctl is-system-running` says running or degraded.
4. `dot sync --no-push` (long first run).
5. `dot status --brief`, `systemctl --user list-timers`, `cat /etc/wsl.conf`.
6. Profile `luca`: `gh auth login`, then `dot secrets unlock --identity <age file>` (or usbipd-win and
   `dot secrets unlock`).

## Unattended

No tty or `BOOTSTRAP_ASSUME_YES=1`: answers from env. `BOOTSTRAP_{USERNAME,DISK,PASSWORD,USER_PASSWORD,ROOT_PASSWORD,
KEYMAP}` (keymap default de-latin1, loaded at once; `BOOTSTRAP_KEYMAP_DEFAULT` only preselects; no username default),
`BOOTSTRAP_PROFILE` (default custom), `BOOTSTRAP_PLATFORM=<host>|server|custom` (default custom; the `bootstrap.sh`
argument wins), `BOOTSTRAP_HOME_NETWORK=0|1`, `BOOTSTRAP_ENCRYPT=0|1` (default 1); server or custom also
`BOOTSTRAP_{HOSTNAME,GROUPS,TIMEZONE,LOCALE,SSH_KEY}` and `BOOTSTRAP_SECURE_BOOT`. `BOOTSTRAP_SERVER=1` turns custom
into server. Each question's `env` and `default` is the reference. `dot test run` drives this through an answer file
(`--profile`, default luca; `report` makes the stages beacon and upload logs, skill `l-dotfiles-vm-test`).

## Check the chain

1. `/var/lib/dotfiles-stage/log`: one `<stage>: ok` per stage.
2. `install.log`, `config.log`, `FAILURES.install`, `FAILURES.config` in the checkout; `/var/log/lsck0-install.log`.
3. The install stage goes on by `/var/lib/dotfiles/install-pass`, not by dot's exit code (`stage-next` in
   `scripts/lib/stage.nu`). Pass written: config, even after a partial pass; modules whose packages are missing stay
   pending (exit 3, `dot status`). No pass: a reboot retries after a backoff, 3 attempts in all.
4. Third attempt without a pass: the chain stops before config and disarms. The stage LUKS key slot, its keyfile and
   initramfs drop-in go, then `next`, the unit and the passwordless sudoers drop-in; a `stopped` marker stays. The disk
   asks for its passphrase again, sudo for the password, nothing retries by itself. The login banner
   (`/etc/issue.d/dotfiles-stage.issue`) names what failed, the way online on a fail-closed network
   (`dot set --machine base/networkmanager.untrusted_policy firewall-only && dot apply --system`) and the resume.
5. Resume: `dot internal stage` at a terminal. sudo asks once, the drop-in, unit and install stage are armed again, the
   install runs; the key is not re-added, so each later boot of the chain asks for the disk passphrase. Without a tty it
   refuses and names the command.

## Updating

Everyone runs `dot sync`: pull `origin/master` (the submodule only with `secrets`), migrate, install, apply, every
module's `update` verb. Only the machine holding the `SIGNING_KEY_FINGERPRINT` secret key backs up, commits and pushes;
elsewhere it stops after the apply. A non-wheel login converges its user layer only. Local edits are autostashed; a
conflict stops the run; a checkout off `master` refuses.

## Another login

`adduser-dotfiles <name> [--profile luca|custom]` (root-owned sh wrapper, runs `adduser` through sudo): creates the user
(never wheel), its checkout, profile and user layer (one `dot apply --packages --user` in a login session through
`systemd-run`). Without `--profile` it asks on a tty, else `custom`. Rerun-safe; an existing `profile.nuon` is kept. A
`secrets` profile adds the login to `/var/lib/dotfiles/owners`, from which `configs/secrets/yubikey` maps their YubiKey
in `/etc/u2f_mappings` on the next system run (without the submodule, sudo takes the password).

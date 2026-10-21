---
name: l-dotfiles-install
description: Installing a machine from this repo (owner, generic, WSL), how the unattended boot chain runs, and adding another login on an installed machine. Load when setting up or reinstalling a machine or user.
---

# install

Three stages: `bootstrap.sh` (from the ISO: nushell and a verified checkout, then `dot internal bootstrap`: keyboard
layout first, disk, base system, user, root copy, arms the chain), then `dot internal stage` runs `dot apply --packages`
and `dot apply` on their own boots, unattended, and retires itself and its sudo drop-in at the end.

## Install

1. Easy: Arch Linux-LSCK0, https://mirror.lsck0.dev/iso/archlinux-lsck0-latest-x86_64.iso (verify with its `.sha256`
   and `.sig`), written raw to a stick. Its stub autologins on tty1, waits for internet
   (cable automatic, else the answer file's `wifi` or a picker; it never starts offline), clones the newest master,
   checks HEAD against the signing key baked into the iso and runs that checkout's `bootstrap.sh` with
   `LSCK0_INSTALL=1`, which starts `dot internal iso-install` (`scripts/lib/iso-install.nu`): the answer file
   (`lsck0.nuon` on a FAT32 partition labelled `LSCK0` and other places, keys in `mirror/iso/lsck0.example.nuon`)
   and `lsck0.*` boot parameters as `BOOTSTRAP_*`, then `dot internal bootstrap`. An answered key is not asked;
   `unattended: true` skips the summary too, asks each `"ask"` password once on the console before it starts, and
   tees the run to `/tmp/lsck0-install.log`, copied to the new system's `/var/log/lsck0-install.log`. Unattended, a
   disk whose ESP holds `/boot/dotfiles-stage-in-progress` (its chain still running: a stick left in and booted first)
   is refused unless `reinstall: true` (`BOOTSTRAP_REINSTALL=1`, best the one-boot `lsck0.reinstall=1`). Before the
   reboot `efibootmgr --bootnext` points the firmware at the new ESP's entry, and each stage reboot sets BootNext to
   the entry it booted from. The answer file's `source` (an unverified tree on top of master, the vm test's) is used
   only with `lsck0.insecure=1`, inside a VM, or after a yes on the console (the stub's `source-allowed`).
   Frozen on the stick: only the stub's network, clone and signature check, and the trust anchor; a newer stub on
   master replaces the stick's once verified. Questions,
   answer-file keys and validation, the env mapping and everything after come from master at install time, so a
   change there needs no reburn; a change to how the stub gets online or clones, the repo url or the signing key does
   (the frozen part is the stub's first half, `mirror/iso/airootfs/usr/local/bin/lsck0-install` up to its newer-stub
   switch, plus the trust anchor taken from `bootstrap.sh` at build time).
2. Alternative, from the official Arch ISO:

   ```bash
   curl -fsSL https://install-linux.lsck0.dev | sh
   ```

Build the iso with `dot internal iso` (needs root for mkarchiso).

- `bootstrap.sh` (about 50 lines of bash, the official iso has no nu) runs only on the Arch ISO or in WSL, installs nushell
  (growing the iso's overlay when it is too small), clones master and refuses to run anything unless HEAD is signed by
  `SIGNING_KEY_FINGERPRINT` (`BOOTSTRAP_INSECURE=1` skips that). From an existing checkout (dot test run, the lsck0 stub's verified clone) it skips the clone.
- Questions live in `scripts/lib/bootstrap/questions.nuon`, in the order they are asked: id (the answer-file key),
  kind, title, text, options, default, `BOOTSTRAP_*` env var and `when` (the walker in `bootstrap.nu` is the
  reference); a top-level `answers` list holds the answer-file-only keys. Its
  `messages` and `summary` hold every other text (welcome, errors, summary rows), and the lsck0 iso's second stage
  takes the answer file's keys and types from it (the iso's Wi-Fi screens are frozen in its stub). Wording, order or a new question is an
  edit there; `bootstrap.nu` only walks the list (code steps like `platform-load` and `install-checks` are entries
  with `step`). Order: keyboard, login name, profile, machine, home network, then per machine, disk, encryption,
  passwords, summary. Nothing is written before the summary's `install`.
- Login name, profile and machine are three separate choices; nothing is derived from the login name.
- Profile: a `profiles/<name>.nuon` (luca) or `custom` (the default: no file, no capabilities, so nothing personal). The picked file is copied to `~/.config/dotfiles/profile.nuon`.
- Machine: a `platforms/<name>.nuon`, labelled by form factor (`pc`, `notebook`; on WSL only `wsl`), recorded in
  `/etc/dotfiles/platform`; then `server` (not on WSL) and `custom`. Both ask hostname and an ssh public key for
  `~/.ssh/authorized_keys` (empty: console only, sshd takes no passwords), off WSL also timezone, locale and secure
  boot; both write the root-owned `/etc/dotfiles/platform.nuon` (and `.options.nuon`) and drop
  `/etc/dotfiles/platform`. `server` takes `platforms/server.nuon` (base plus docker, no desktop), `custom` asks the
  package groups. `vm` and `server` are left out of the machine list (the platform question's `hidden`; `server` is
  offered as its own option), the vm test passes `vm` by argument.
- Every machine asks whether to encrypt the disk (LUKS2, default yes); server and custom also ask for secure boot:
  `own` keys, `microsoft` (own keys plus Microsoft's, the default) or `off`.
- Prompt texts stay short: one question, the options, at most one line of context for a risky choice.

## WSL

Run the same line in a fresh Arch distro's root shell. No disk, bootloader or stage chain: keyring, upgrade, wheel
user, `wsl.conf`, verified repo. Then terminate the distro, reopen it, and run `dot sync --no-push`. The `wsl` machine
is groups base, core, programming, with no homelab fact; its options turn off the firewall (nftables, portmaster,
fail2ban, endlessh, ossec), vpn (protonvpn, protonvpn-netns, wireguard) and tor modules.

## Unattended runs

Without a tty, or with `BOOTSTRAP_ASSUME_YES=1`, every answer comes from env: `BOOTSTRAP_{USERNAME,DISK,PASSWORD,
USER_PASSWORD,ROOT_PASSWORD,KEYMAP}` (the keymap, de-latin1 by default, is the first question and is loaded at once;
the username has no default), `BOOTSTRAP_PROFILE=<name>|custom` (default custom), `BOOTSTRAP_PLATFORM=<host>|server|
custom` (default custom; the argument to `bootstrap.sh` wins), `BOOTSTRAP_HOME_NETWORK=0|1` and `BOOTSTRAP_ENCRYPT=0|1`
(default 1); for server or custom also `BOOTSTRAP_{HOSTNAME,GROUPS,TIMEZONE,LOCALE,SSH_KEY}` and
`BOOTSTRAP_SECURE_BOOT=own|microsoft|off` (default microsoft). The old `BOOTSTRAP_SERVER=1` still turns custom into
server. `BOOTSTRAP_REINSTALL=1` lets it erase a disk still in its install chain. Each question's `env` and `default` in `scripts/lib/bootstrap/questions.nuon` is the reference. `dot test run` drives exactly this, passes
`--profile` (default luca) as `BOOTSTRAP_PROFILE` and `BOOTSTRAP_{SERVER,SECURE_BOOT,HOSTNAME,GROUPS,SSH_KEY}` from the
host into the guest (skill `l-dotfiles-vm-test`).

## Check the chain

1. `/var/lib/dotfiles-stage/log`: one `<stage>: ok` line per stage.
2. `install.log`, `config.log`, `FAILURES.install`, `FAILURES.config` in the checkout; an unattended lsck0 install's
   first part is `/var/log/lsck0-install.log`.
3. An aborted `dot apply --packages` (exit 2) is retried on the next boot, 3 attempts in all; after the third the
   chain moves on to config and `dot apply --packages` is rerun by hand.

## Another login on an installed machine

```bash
adduser-dotfiles <name> [--profile luca|custom]
```

Root-owned `/usr/local/bin/adduser-dotfiles`, a sh wrapper `system-apply.nu` writes that runs its `adduser` through
sudo: creates the user (never wheel), its own
checkout, profile and user layer. Without `--profile` it asks on a tty and takes `custom` otherwise. Rerun-safe; an
existing `profile.nuon` is kept. A profile with the `secrets` capability adds the login to root's owner registry
`/var/lib/dotfiles/owners` (the bootstrap does the same for the first login), from which the owner's module
`configs/secrets/yubikey` maps their YubiKey in `/etc/u2f_mappings` on the next system run (`base/pam` reads it;
without the submodule there is no mapping and sudo takes the password).

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
   and `.sig`, `mirror/iso/README.md`), written raw to a stick. It autologins on tty1, reads an optional answer file
   (`lsck0.nuon` on a FAT32 partition labelled `LSCK0` and other places, keys in `mirror/iso/lsck0.example.nuon`),
   waits for internet (cable automatic, else a Wi-Fi picker; it never starts offline), then runs the same
   `bootstrap.sh` as below. An answered key is not asked; `unattended: true` skips the summary too.
2. Alternative, from the official Arch ISO:

   ```bash
   curl -fsSL https://install-linux.lsck0.dev | sh
   ```

Build the iso with `dot internal iso` (needs root for mkarchiso, `mirror/iso/README.md`).

- `bootstrap.sh` (under 50 lines of bash, the iso has no nu) runs only on the Arch ISO or in WSL, installs nushell
  (growing the iso's overlay when it is too small), clones master and refuses to run anything unless HEAD is signed by
  `SIGNING_KEY_FINGERPRINT` (`BOOTSTRAP_INSECURE=1` skips that). From an existing checkout (dot test run) it skips the clone.
- Questions in order: keyboard, login name, profile, machine, home network, then per machine, disk, encryption,
  passwords, summary. Nothing is written before the summary's `install`.
- Login name, profile and machine are three separate choices; nothing is derived from the login name.
- Profile: a `profiles/<name>.nuon` (luca) or `custom` (the default: no file, no capabilities, so no secrets, identity,
  homelab or work). The picked file is copied to `~/.config/dotfiles/profile.nuon`.
- Machine: the `platforms/<host>.nuon` for this kind of host, labelled by form factor (PC luca-pc, notebook
  luca-notebook; on WSL only WSL luca-wsl), then `server` and `custom`. Both ask hostname, timezone, locale and secure
  boot and write the root-owned `/etc/dotfiles/platform.nuon`; `server` takes `platforms/templates/server.nuon` (base
  plus docker, no desktop) and an ssh public key, `custom` the package groups. `test-vm` is left out
  (`PLATFORMS_HIDDEN`), the vm test passes it by argument.
- Every machine asks whether to encrypt the disk (LUKS2, default yes); server and custom also ask for secure boot:
  `own` keys, `microsoft` (own keys plus Microsoft's, the default) or `off`.
- Prompt texts stay short: one question, the options, at most one line of context for a risky choice.

## WSL

Run the same line in a fresh Arch distro's root shell. No disk, bootloader or stage chain: keyring, upgrade, wheel
user, `wsl.conf`, verified repo. Then terminate the distro, reopen it, and run `dot sync --no-push`.

## Unattended runs

Without a tty, or with `BOOTSTRAP_ASSUME_YES=1`, every answer comes from env: `BOOTSTRAP_{USERNAME,DISK,PASSWORD,
USER_PASSWORD,ROOT_PASSWORD,KEYMAP}` (the keymap, de-latin1 by default, is the first question and is loaded at once;
the username has no default), `BOOTSTRAP_PROFILE=<name>|custom` (default custom), `BOOTSTRAP_PLATFORM=<host>|server|
custom` (default custom; the argument to `bootstrap.sh` wins), `BOOTSTRAP_HOME_NETWORK=0|1` and `BOOTSTRAP_ENCRYPT=0|1`
(default 1); for server or custom also `BOOTSTRAP_{HOSTNAME,GROUPS,TIMEZONE,LOCALE,SSH_KEY}` and
`BOOTSTRAP_SECURE_BOOT=own|microsoft|off` (default microsoft). The old `BOOTSTRAP_SERVER=1` still turns custom into
server. The header of `scripts/lib/bootstrap.nu` is the reference. `dot test run` drives exactly this, passes
`--profile` (default luca) as `BOOTSTRAP_PROFILE` and `BOOTSTRAP_{SERVER,SECURE_BOOT,HOSTNAME,GROUPS,SSH_KEY}` from the
host into the guest (skill `l-dotfiles-vm-test`).

## Check the chain

1. `/var/lib/dotfiles-stage/log`: one `<stage>: ok` line per stage.
2. `install.log`, `config.log`, `FAILURES.install`, `FAILURES.config` in the checkout.
3. An aborted `dot apply --packages` (exit 2) is retried on the next boot, up to 3 times; after that the chain moves
   on to config and `dot apply --packages` is rerun by hand.

## Another login on an installed machine

```bash
adduser-dotfiles <name> [--profile luca|custom]
```

Root-owned `/usr/local/bin/adduser-dotfiles` (linked by `system-apply.nu`): creates the user (never wheel), its own
checkout, profile and user layer. Without `--profile` it asks on a tty and takes `custom` otherwise. Rerun-safe; an
existing `profile.nuon` is kept.

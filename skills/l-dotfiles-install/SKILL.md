---
name: l-dotfiles-install
description: Installing a machine from this repo (owner, generic, WSL), how the unattended boot chain runs, and adding another login on an installed machine. Load when setting up or reinstalling a machine or user.
---

# install

Three stages: `bootstrap.sh` (from the ISO: nushell and a verified checkout, then `dot internal bootstrap`: keyboard
layout first, disk, base system, user, root copy, arms the chain), then `dot internal stage` runs `dot apply --packages`
and `dot apply` on their own boots, unattended, and retires itself and its sudo drop-in at the end.

## Install

```bash
curl -fsSL https://install-linux.lsck0.dev | sh
```

- `bootstrap.sh` (under 50 lines of bash, the iso has no nu) runs only on the Arch ISO or in WSL, installs nushell
  (growing the iso's overlay when it is too small), clones master and refuses to run anything unless HEAD is signed by
  `SIGNING_KEY_FINGERPRINT` (`BOOTSTRAP_INSECURE=1` skips that). From an existing checkout (dot test run) it skips the clone.
- The machine menu lists `platforms/<host>.nuon` (luca-pc, luca-notebook, luca-wsl) and `custom`. `custom` asks for the
  machine instead; the answers go to the root-owned `/etc/dotfiles/platform.nuon`. It asks "server?" first: yes takes
  `platforms/templates/server.nuon` (base plus docker, no desktop) and an ssh public key. `test-vm` is left out
  (`PLATFORMS_HIDDEN`), the vm test passes it by argument.
- Every machine asks whether to encrypt the disk (LUKS2, default yes); a new one also asks for secure boot: `own` keys,
  `microsoft` (own keys plus Microsoft's, the default) or `off`.
- The profile template `profiles/<user>.nuon` is copied to `~/.config/dotfiles/profile.nuon`; a user without one is a
  guest (no capabilities).

## WSL

Run the same line in a fresh Arch distro's root shell. No disk, bootloader or stage chain: keyring, upgrade, wheel
user, `wsl.conf`, verified repo. Then terminate the distro, reopen it, and run `dot sync --no-push`.

## Unattended runs

Without a tty, or with `BOOTSTRAP_ASSUME_YES=1`, every answer comes from env: `BOOTSTRAP_{USERNAME,DISK,PASSWORD,
USER_PASSWORD,ROOT_PASSWORD,KEYMAP}` (the keymap, de-latin1 by default, is the first question and is loaded at once;
the username has no default) and `BOOTSTRAP_ENCRYPT=0|1` (default 1); for a new machine also
`BOOTSTRAP_{HOSTNAME,GROUPS,TIMEZONE,LOCALE}`, `BOOTSTRAP_HOME_NETWORK=0|1`, `BOOTSTRAP_SERVER=0|1`,
`BOOTSTRAP_SSH_KEY` and `BOOTSTRAP_SECURE_BOOT=own|microsoft|off` (default microsoft). The header of
`scripts/lib/bootstrap.nu` is the reference. `dot test run` drives exactly this and passes
`BOOTSTRAP_{SERVER,SECURE_BOOT,HOSTNAME,GROUPS,SSH_KEY}` from the host into the guest (skill `l-dotfiles-vm-test`).

## Check the chain

1. `/var/lib/dotfiles-stage/log`: one `<stage>: ok` line per stage.
2. `install.log`, `config.log`, `FAILURES.install`, `FAILURES.config` in the checkout.
3. An aborted `dot apply --packages` (exit 2) is retried on the next boot, up to 3 times; after that the chain moves
   on to config and `dot apply --packages` is rerun by hand.

## Another login on an installed machine

```bash
adduser-dotfiles <name>
```

Root-owned `/usr/local/bin/adduser-dotfiles` (linked by `system-apply.nu`): creates the user (never wheel), its own
checkout, profile and user layer. Rerun-safe.

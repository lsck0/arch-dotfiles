---
name: l-dotfiles-install
description: "Installing a machine from this repo (lsck0 iso, Arch ISO one-liner, WSL), the unattended boot chain and resuming a stopped one, its /etc/issue.d banners, what dot sync does, and adduser-dotfiles. Load when setting up or reinstalling a machine or login, when a chain stopped, or to predict a sync. Testing in a VM: l-dotfiles-vm-test."
---

# install

Three stages: `bootstrap.sh` (nushell, a verified checkout, then `dot internal bootstrap`: keyboard, disk, base
system, user, root copy, arms the chain), then `dot internal stage` runs `dot apply --packages` and `dot apply` on
their own boots, unattended. At the end it retires itself and its sudo drop-in, or stops disarmed.

## Install

- lsck0 iso: `https://mirror.lsck0.dev/iso/archlinux-lsck0-latest-x86_64.iso`, checked against `.sha256` and `.sig`
  (key `configs/base/pacman/config/archrepo.asc`, signer `HOMELAB.mirror.isoSigner` in `platforms/homelab.nu`,
  `88042EFBF5F141C2ACF4697ADD84D7C4053DD354`), written raw
  to a stick. Build one with `dot internal iso` (root, mkarchiso). Its stub autologins, waits for internet, clones
  master, checks HEAD's signature and runs `bootstrap.sh`, which starts `dot internal iso-install`.
- From the official Arch ISO: `curl -fsSL https://install-linux.lsck0.dev | sh`.
- WSL: the same line in a fresh Arch distro's root shell; no disk, bootloader or chain.

`bootstrap.sh` (bash, runs only on the Arch ISO or WSL) refuses unless HEAD is signed by `SIGNING_KEY_FINGERPRINT`
(`BOOTSTRAP_INSECURE=1` skips). Nothing is written before the summary's `install`. Login name, profile and machine are
independent; nothing derives from the login name.

Read [reference.md](reference.md) for answer files, the questions, unattended `BOOTSTRAP_*` variables, WSL details and
the sync's due logic.

## Check the chain

1. `/var/lib/dotfiles-stage/log`: one `<stage>: ok` per stage.
2. `install.log`, `config.log`, `FAILURES.install`, `FAILURES.config` in the checkout; `/var/log/lsck0-install.log`.
3. The install stage goes on by `/var/lib/dotfiles/install-pass`, not by dot's exit code (`stage-next` in
   `scripts/lib/stage.nu`). Pass written: on to config, even after a partial pass; modules missing packages stay
   pending (exit 3). No pass: a reboot retries after a backoff, 3 attempts in all, each counted before it runs.
4. Third attempt without a pass: the chain stops before config and disarms. The stage LUKS key slot, keyfile and
   initramfs drop-in go, then `next`, the unit and the passwordless sudoers drop-in; a `stopped` marker stays. The disk
   asks for its passphrase again, sudo for the password, nothing retries. The banner
   `/etc/issue.d/dotfiles-stage.issue` names what failed, how to get online on a fail-closed network
   (`dot set --machine base/networkmanager.untrusted_policy firewall-only && dot apply --system`) and the resume.
5. Resume: Luca runs `dot internal stage` at a terminal (it refuses without a tty). sudo asks once, the chain is
   re-armed and the install runs; the disk key is not re-added, so each later boot asks for the passphrase.
6. A failed config stage also ends the chain disarmed, with `/etc/issue.d/dotfiles-config.issue`; the first full
   `dot apply` (both layers) without failure removes it (`config-banner-clear` in `scripts/lib/run.nu`). A secrets
   profile whose YubiKey was missing gets `dotfiles-secrets.issue`; `base/yubikey` drops it once unlocked.

## Updating

Each login updates with `dot sync`, which is Luca's; agents never run it. One run pulls `origin/master` (submodule
only with `secrets`), migrates, installs, applies, runs every module's `update` verb, and logs to `sync.log`. Root is
entered once, and not at all when nothing is due (`system-due` in `scripts/lib/run.nu`; `--system` forces it). Only
the machine holding the `SIGNING_KEY_FINGERPRINT` secret key backs up, runs `dot internal gen`, commits and pushes. An
unsigned origin head merges nothing; local edits are autostashed; a conflict stops the run; a checkout off `master`
refuses.

## Another login

`adduser-dotfiles <name> [--profile luca|custom]` (root-owned sh wrapper, sudo): creates the user (never wheel), its
checkout, profile and user layer. Without `--profile` it asks on a tty, else `custom`. Rerun-safe; an existing
`profile.nuon` is kept. A `secrets` profile adds the login to `/var/lib/dotfiles/owners`, from which
`configs/secrets/yubikey` maps their YubiKey in `/etc/u2f_mappings` on the next system run.

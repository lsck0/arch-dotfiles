# base/boot

Extends the root `AGENTS.md` and the `configs/base/AGENTS.md`. The boot chain: UKIs, secure boot, luks unlock.
Root only.

## Layout

- `boot.nu`: the steps the boot modules share: `esp-supported`, `cmdline-set`/`cmdline-unset` (edit
  `/etc/kernel/cmdline` by key), `hooks-read`/`hooks-write`/`hooks-insert` (the live `HOOKS=(` line of
  `/etc/mkinitcpio.conf`), called from each module's own `step` commands; `boot-commit`, the system layer's boot
  barrier: one UKI rebuild when `BOOT_INPUTS` (everything mkinitcpio reads) changed, then every boot file signed.
- `systemd-boot/`: the bootloader install.
- `sbctl/`: secure boot key enrollment and signing (signs the UKIs and systemd-boot). Own keys only with the
  `secure_boot_own_keys` fact, else Microsoft's CA stays; off through its `enable` option (bootstrap's secure boot
  answer for a new machine).
- `luks/`: the root disk encryption unlock (keyfile/crypttab.initramfs); declares nothing on a disk without LUKS
  (bootstrap's `BOOTSTRAP_ENCRYPT=0`).
- `remote-unlock/`: an initramfs tinyssh server to unlock luks over the network at boot (host key, authorized key,
  network and port drop-in, all in `BOOT_INPUTS`).
- `hardening/`: boot-path hardening.

## Conventions

- Only archinstall's layout is supported: UEFI, the FAT ESP at `/boot`, root on a btrfs subvol. `esp-supported`
  refuses anything else. linux-lts is the fallback kernel.
- Each kernel preset builds exactly one UKI, its cmdline embedded from `/etc/kernel/cmdline` alone; nothing adds root
  args at boot. systemd-boot finds the UKI in `EFI/Linux` with no entry file; sbctl signs it.
- The boot barrier (`boot-commit` in `boot.nu`, last step of `system-apply.nu config`) rebuilds the initramfs once per run, only when a `BOOT_INPUTS` entry changed
  (content or mode), keyed by a stamp. A module that changes what mkinitcpio reads adds its path to `BOOT_INPUTS`.
- Presets are backed up (`*.arch-dotfiles-backup`) before the first rewrite.

See the `l-dotfiles-install` skill for the full unattended boot chain (bootstrap, stages).

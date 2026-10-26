# base/boot

Root only. UKIs, secure boot, LUKS unlock. Full install chain: `l-dotfiles-install`.

- Only archinstall's layout: UEFI, FAT ESP at `/boot`, root on a btrfs subvol (`esp-supported` refuses others).
  linux-lts is the fallback kernel.
- One UKI per kernel preset, cmdline only from `/etc/kernel/cmdline` (edit with `cmdline-set`/`cmdline-unset` in
  `boot.nu`); systemd-boot finds it in `EFI/Linux`, sbctl signs it.
- `boot-commit` (last step of `system-apply.nu config`) rebuilds the initramfs once, only when a `BOOT_INPUTS` path
  changed. A module that changes what mkinitcpio reads adds its path there.
- `sbctl`: own keys only with the `secure_boot_own_keys` fact, else Microsoft's CA stays.
- `luks` declares nothing without LUKS; `remote-unlock`: see its README.

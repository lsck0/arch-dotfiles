# base/boot

Root only. UKIs, secure boot, LUKS unlock. Full install chain: `l-dotfiles-install`.

- Only archinstall's layout: UEFI, FAT ESP at `/boot`, root on a btrfs subvol (`esp-supported` refuses others).
  linux-lts is the fallback kernel.
- One UKI per kernel preset, cmdline only from `/etc/kernel/cmdline` (edit with `cmdline-set`/`cmdline-unset` in
  `boot.nu`); systemd-boot finds it in `EFI/Linux`, sbctl signs it.
- `boot-commit` is `systemd-boot`'s barrier (`meta.barrier`): the engine runs it once after a system run that changed a
  `BOOT_WATCH` path (`boot.nu`) or that a declaration's `--notify base/boot/systemd-boot` flagged, and again after it
  failed. A module writing a new initramfs input adds its path there or notifies. `hooks-sweep` drops a HOOKS entry
  whose install script is gone, on every run.
- `sbctl`: own keys only with the `secure_boot_own_keys` fact, else Microsoft's CA stays.
- `luks` declares nothing without LUKS; `remote-unlock`: see its README.

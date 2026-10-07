#!/usr/bin/env bash
# drop the timeshift snapshot boot menu and the plain initramfs images, gone since grub chainloads one signed uki per kernel

set -euo pipefail

sudo rm -f /etc/grub.d/41_timeshift /etc/pacman.d/hooks/zz-boot-menu.hook /boot/grub/timeshift.cfg

for preset in /etc/mkinitcpio.d/*.preset; do
    [[ -f "$preset" ]] || continue
    uki=$(sed -n 's/^default_uki="\?\([^"]*\)"\?$/\1/p' "$preset")
    [[ -n "$uki" ]] || continue
    pkgbase=$(basename "$preset" .preset)
    # pending until the boot barrier built the uki and grub.cfg stopped booting the plain image
    sudo test -f "$uki" || exit 1
    if sudo grep -qF -e "/initramfs-$pkgbase.img" -e "/initramfs-$pkgbase-fallback.img" /boot/grub/grub.cfg 2>/dev/null; then
        exit 1
    fi
    sudo rm -f "/boot/initramfs-$pkgbase.img" "/boot/initramfs-$pkgbase-fallback.img"
done

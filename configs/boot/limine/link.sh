#!/usr/bin/env bash

set -ex

source "$(dirname "$0")/../boot-menu/common.sh"

if ! bootloader_selected limine; then
    exit 0
fi
if [[ ! -f /usr/share/limine/BOOTX64.EFI ]]; then
    echo "limine: selected in boot.conf but not installed" >&2
    exit 1
fi
esp_supported || exit 0

HERE="$(cd "$(dirname "$0")" && pwd)"

enable_initramfs_images
install_boot_menu limine

# archinstall deploys limine when it was picked there; otherwise deploy it now.
LIMINE_EFI="$(sudo /usr/local/bin/boot-menu limine-efi)"
if [[ -z "$LIMINE_EFI" ]]; then
    LIMINE_EFI="$ESP/EFI/limine/BOOTX64.EFI"
    sudo install -Dm644 /usr/share/limine/BOOTX64.EFI "$LIMINE_EFI"
fi
sed "s|@LIMINE_EFI@|$LIMINE_EFI|" "$HERE/limine-deploy.hook" | sudo tee /etc/pacman.d/hooks/limine-deploy.hook >/dev/null

# Firmware entry for limine, first in BootOrder.
loader="${LIMINE_EFI#"$ESP"}"
loader="${loader//\//\\}"
num="$(sudo efibootmgr | L="$loader" awk 'index(tolower($0), tolower(ENVIRON["L"])) { print substr($1, 5, 4); exit }')"
if [[ -z "$num" ]]; then
    esp_dev="$(findmnt -n -o SOURCE "$ESP")"
    sudo efibootmgr --create --disk "/dev/$(lsblk -no PKNAME "$esp_dev")" \
        --part "$(cat "/sys/class/block/$(basename "$esp_dev")/partition")" \
        --label Limine --loader "$loader" >/dev/null
else
    efi_boot_first "$num"
fi

# GRUB is not the bootloader any more; its menu scripts stay but nothing runs them.
sudo rm -f /etc/pacman.d/hooks/grub-disable-10_linux.hook

# Writes limine.conf (kernels + timeshift snapshots) and signs the limine binary.
sudo /usr/local/bin/boot-menu limine

sbctl_sign "$ESP"/vmlinuz-*

echo "limine: configured and first in BootOrder" >&2

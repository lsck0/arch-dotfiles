# shellcheck shell=bash Shared by configs/boot/{grub,limine}/link.sh.

BOOT_MENU_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BOOT_STATE="$HOME/projects/arch-dotfiles/boot.conf"
ESP=/boot

bootloader_selected() {
    [[ -f "$BOOT_STATE" ]] && grep -qx "$1" "$BOOT_STATE"
}

esp_supported() {
    if [[ ! -d /sys/firmware/efi ]]; then
        echo "boot: not UEFI (no /sys/firmware/efi) — only the EFI layout is supported" >&2
        return 1
    fi
    if [[ "$(stat -f -c %T "$ESP")" != msdos ]]; then
        echo "boot: $ESP is not the FAT ESP — only archinstall's ESP-at-/boot layout is supported" >&2
        return 1
    fi
    if [[ ! -f "$ESP/vmlinuz-linux-lts" ]]; then
        echo "boot: linux-lts not installed — snapshots without matching linux modules get no fallback kernel" >&2
    fi
}

# Snapshot entries boot vmlinuz + initramfs from the ESP, so UKI-only presets also build a plain initramfs.
enable_initramfs_images() {
    local preset pkgbase rebuild=false
    for preset in /etc/mkinitcpio.d/*.preset; do
        [[ -f "$preset" ]] || continue
        grep -q '^default_uki=' "$preset" || continue
        grep -q '^default_image=' "$preset" && continue
        pkgbase="$(basename "$preset" .preset)"
        if [[ ! -e "${preset}.arch-dotfiles-backup" ]]; then
            sudo install -m644 "$preset" "${preset}.arch-dotfiles-backup"
        fi
        sudo sed -i '/^#default_image=/d' "$preset"
        echo "default_image=\"/boot/initramfs-${pkgbase}.img\"" | sudo tee -a "$preset" >/dev/null
        rebuild=true
    done
    if [[ "$rebuild" == "true" ]]; then
        sudo mkinitcpio -P
    fi
}

# boot-menu plus what keeps its entries current: a pacman hook and a timer.
install_boot_menu() {
    local mode="$1"
    sudo install -Dm755 "$BOOT_MENU_DIR/boot-menu" /usr/local/bin/boot-menu
    sudo mkdir -p /etc/pacman.d/hooks
    sed "s|@MODE@|$mode|" "$BOOT_MENU_DIR/zz-boot-menu.hook" | sudo tee /etc/pacman.d/hooks/zz-boot-menu.hook >/dev/null
    sed "s|@MODE@|$mode|" "$BOOT_MENU_DIR/boot-menu.service" | sudo tee /etc/systemd/system/boot-menu.service >/dev/null
    sudo install -Dm644 "$BOOT_MENU_DIR/boot-menu.timer" /etc/systemd/system/boot-menu.timer
    sudo systemctl daemon-reload
    sudo systemctl enable boot-menu.timer
}

# Move boot entry $1 to the front of the firmware BootOrder.
efi_boot_first() {
    local num="$1" order n rest=()
    order="$(sudo efibootmgr | sed -n 's/^BootOrder: //p')"
    IFS=, read -ra current <<<"$order"
    for n in "${current[@]}"; do
        [[ "$n" == "$num" ]] || rest+=("$n")
    done
    sudo efibootmgr -o "$(IFS=,; echo "${num}${rest[*]:+,${rest[*]}}")" >/dev/null
}

# Sign boot files if sbctl keys exist.
sbctl_sign() {
    command -v sbctl >/dev/null 2>&1 || return 0
    sudo sbctl status 2>/dev/null | grep -qE 'Owner GUID' || return 0
    local f
    for f in "$@"; do
        if [[ -f "$f" ]]; then
            sudo sbctl sign -s "$f"
        fi
    done
}

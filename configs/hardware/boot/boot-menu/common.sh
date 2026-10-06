# shellcheck shell=bash

BOOT_MENU_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# archinstall mounts the ESP fmask/dmask=0077, so file tests under it need sudo
ESP=/boot
# everything mkinitcpio and grub-mkconfig read; config.sh's boot barrier rebuilds once when their content or mode changed
BOOT_INPUTS=(/etc/mkinitcpio.conf /etc/mkinitcpio.conf.d /etc/mkinitcpio.d /etc/kernel/cmdline /etc/crypttab.initramfs
    /etc/default/grub /etc/grub.d /etc/plymouth /usr/share/plymouth/themes)
BOOT_INPUTS_STAMP="${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles/boot-inputs"

esp_supported() {
    if [[ ! -d /sys/firmware/efi ]]; then
        echo "boot: not UEFI (no /sys/firmware/efi), only the EFI layout is supported" >&2
        return 1
    fi
    if [[ "$(stat -f -c %T "$ESP")" != msdos ]]; then
        echo "boot: $ESP is not the FAT ESP, only archinstall's ESP-at-/boot layout is supported" >&2
        return 1
    fi
    if ! sudo test -f "$ESP/vmlinuz-linux-lts"; then
        echo "boot: linux-lts not installed, snapshots without matching linux modules get no fallback kernel" >&2
    fi
}

# snapshot entries need a plain initramfs, even with uki presets
enable_initramfs_images() {
    local preset pkgbase
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
    done
}

# kernel_cmdline_set <token>...: each token replaces the tokens of its key (text before the first =) in /etc/kernel/cmdline
kernel_cmdline_set() {
    local file=/etc/kernel/cmdline token word words=() kept=()
    if [[ ! -f "$file" ]]; then
        tr ' ' '\n' </proc/cmdline | grep -vE '^(BOOT_IMAGE|initrd)=' | paste -sd' ' | sudo install -Dm644 /dev/stdin "$file"
    fi
    [[ -e "$file.arch-dotfiles-backup" ]] || sudo install -m644 "$file" "$file.arch-dotfiles-backup"
    read -ra words <"$file"
    for token in "$@"; do
        kept=()
        for word in "${words[@]}"; do
            [[ "${word%%=*}" == "${token%%=*}" && "$word" != "$token" ]] || kept+=("$word")
        done
        words=("${kept[@]}")
        [[ " ${words[*]} " == *" $token "* ]] || words+=("$token")
    done
    # grub.cfg and the initramfs pick it up at config.sh's boot barrier
    [[ "${words[*]}" == "$(<"$file")" ]] || echo "${words[*]}" | sudo tee "$file" >/dev/null
}

install_boot_menu() {
    local mode="$1"
    sudo install -Dm755 "$BOOT_MENU_DIR/boot-menu" /usr/local/bin/boot-menu
    sed "s|@MODE@|$mode|" "$BOOT_MENU_DIR/zz-boot-menu.hook" | sudo install -Dm644 /dev/stdin /etc/pacman.d/hooks/zz-boot-menu.hook
    sed "s|@MODE@|$mode|" "$BOOT_MENU_DIR/boot-menu.service" | sudo install -Dm644 /dev/stdin /etc/systemd/system/boot-menu.service
    sudo install -Dm644 "$BOOT_MENU_DIR/boot-menu.timer" /etc/systemd/system/boot-menu.timer
    sudo systemctl daemon-reload
    sudo systemctl enable boot-menu.timer
}

# sbctl_ready: keys exist, so boot files get signed; before configs/hardware/boot/sbctl ran there is nothing to sign with
sbctl_ready() {
    command -v sbctl >/dev/null 2>&1 && sudo sbctl status | grep -qE 'Owner GUID'
}

sbctl_sign() {
    sbctl_ready || return 0
    local f
    for f in "$@"; do
        if sudo test -f "$f"; then
            sudo sbctl sign -s "$f"
        fi
    done
}

# boot_commit: the boot barrier, one initramfs and grub.cfg rebuild for every change of the run, then every boot file signed and verified
boot_commit() {
    local inputs unsigned
    # wsl: windows boots its own kernel, there is no initramfs or bootloader here
    command -v mkinitcpio >/dev/null 2>&1 || return 0
    # inputs this machine lacks (no plymouth, no crypttab.initramfs) hash as absent
    inputs=$(sudo find "${BOOT_INPUTS[@]}" -type f -printf '%m %p\n' -exec sha256sum {} + 2>/dev/null | sha256sum)
    if [[ "$inputs" != "$(cat "$BOOT_INPUTS_STAMP" 2>/dev/null)" ]]; then
        sudo mkinitcpio -P || return 1
        if sudo test -f "$ESP/grub/grub.cfg"; then
            sudo grub-mkconfig -o "$ESP/grub/grub.cfg" || return 1
        fi
        mkdir -p "${BOOT_INPUTS_STAMP%/*}"
        echo "$inputs" >"$BOOT_INPUTS_STAMP"
    fi
    sbctl_ready || return 0
    sudo sbctl sign-all || return 1
    unsigned=$(sudo sbctl verify | grep 'is not signed')
    if [[ -n "$unsigned" ]]; then
        echo "boot: unsigned with secure boot keys enrolled, the next boot may fail: $unsigned" >&2
        return 1
    fi
}

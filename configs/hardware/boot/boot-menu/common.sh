# shellcheck shell=bash

BOOT_MENU_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# archinstall mounts the ESP fmask/dmask=0077, so file tests under it need sudo
ESP=/boot
UKI_DIR="$ESP/EFI/Linux"
CMDLINE=/etc/kernel/cmdline
# everything mkinitcpio and grub-mkconfig read; config.sh's boot barrier rebuilds once when their content or mode changed
BOOT_INPUTS=(/etc/mkinitcpio.conf /etc/mkinitcpio.conf.d /etc/mkinitcpio.d "$CMDLINE" /etc/crypttab.initramfs
    /etc/default/grub /etc/grub.d /usr/local/bin/boot-menu /etc/plymouth /usr/share/plymouth/themes)
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
        echo "boot: linux-lts not installed, no fallback kernel when linux breaks" >&2
    fi
}

# enable_ukis: each kernel preset builds one uki, its cmdline embedded from $CMDLINE alone; grub only chainloads it, sbctl signs it
enable_ukis() {
    local preset want
    kernel_cmdline_set
    # nothing adds root arguments at boot any more
    if ! grep -qE '(^| )root=' "$CMDLINE" || { [[ "$(findmnt -no FSROOT /)" != / ]] && ! grep -q 'subvol=' "$CMDLINE"; }; then
        echo "boot: $CMDLINE lacks root= or the root subvol, not switching to ukis" >&2
        return 1
    fi
    for preset in /etc/mkinitcpio.d/*.preset; do
        [[ -f "$preset" ]] || continue
        want=$(sed -e "s/^PRESETS=.*/PRESETS=('default')/" -e '/^#\?default_\(image\|uki\|cmdline\)=/d' "$preset"
            printf 'default_uki="%s"\ndefault_cmdline="%s"\n' "$UKI_DIR/arch-$(basename "$preset" .preset).efi" "$CMDLINE")
        [[ "$want" == "$(<"$preset")" ]] && continue
        [[ -e "$preset.arch-dotfiles-backup" ]] || sudo install -m644 "$preset" "$preset.arch-dotfiles-backup"
        echo "$want" | sudo tee "$preset" >/dev/null
    done
}

# kernel_cmdline_set <token>...: each token replaces the tokens of its key (text before the first =) in $CMDLINE
kernel_cmdline_set() {
    local file=$CMDLINE token word words=() kept=()
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
    # the ukis pick it up at config.sh's boot barrier
    [[ "${words[*]}" == "$(<"$file")" ]] || echo "${words[*]}" | sudo tee "$file" >/dev/null
}

# kernel_cmdline_unset <key>: drops every token of that key from $CMDLINE
kernel_cmdline_unset() {
    local file=$CMDLINE word words=() kept=()
    [[ -f "$file" ]] || return 0
    [[ -e "$file.arch-dotfiles-backup" ]] || sudo install -m644 "$file" "$file.arch-dotfiles-backup"
    read -ra words <"$file"
    for word in "${words[@]}"; do
        [[ "${word%%=*}" == "$1" ]] || kept+=("$word")
    done
    [[ "${kept[*]}" == "$(<"$file")" ]] || echo "${kept[*]}" | sudo tee "$file" >/dev/null
}

install_boot_menu() {
    sudo install -Dm755 "$BOOT_MENU_DIR/boot-menu" /usr/local/bin/boot-menu
    # the snapshot menu it refreshed is gone
    if [[ -e /etc/systemd/system/boot-menu.timer ]]; then
        sudo systemctl disable --now boot-menu.timer
        sudo rm -f /etc/systemd/system/boot-menu.{service,timer}
        sudo systemctl daemon-reload
    fi
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

# boot_commit: the boot barrier, one uki and grub.cfg rebuild for every change of the run, then every boot file signed and verified
boot_commit() {
    local inputs preset unsigned
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
    # sign -s lists each uki in sbctl's database, so sign-all and sbctl's pacman hook re-sign it after every kernel upgrade
    for preset in /etc/mkinitcpio.d/*.preset; do
        sbctl_sign "$UKI_DIR/arch-$(basename "$preset" .preset).efi"
    done
    sudo sbctl sign-all || return 1
    unsigned=$(sudo sbctl verify | grep 'is not signed')
    # the plain kernels stay unsigned once grub.cfg stops booting them: grub.cfg could chainload a signed one with any cmdline and initrd
    sudo grep -qE '^\s*linux\s+/vmlinuz-' "$ESP/grub/grub.cfg" 2>/dev/null || unsigned=$(grep -v "$ESP/vmlinuz-" <<<"$unsigned")
    if [[ -n "$unsigned" ]]; then
        echo "boot: unsigned with secure boot keys enrolled, the next boot may fail: $unsigned" >&2
        return 1
    fi
}

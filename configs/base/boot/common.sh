# shellcheck shell=bash
# root only: sourced by the boot-touching system.sh modules and by system-apply.sh for boot_commit

# archinstall mounts the ESP fmask/dmask=0077, only root reads it
ESP=/boot
UKI_DIR="$ESP/EFI/Linux"
CMDLINE=/etc/kernel/cmdline
# systemd-boot's source and its two copies on the esp; bootctl copies systemd-bootx64.efi.signed instead when it exists
SDBOOT_EFI=/usr/lib/systemd/boot/efi/systemd-bootx64.efi
SDBOOT_ESP_FILES=("$ESP/EFI/systemd/systemd-bootx64.efi" "$ESP/EFI/BOOT/BOOTX64.EFI")
# everything mkinitcpio reads; system-apply's boot barrier rebuilds once when their content or mode changed
BOOT_INPUTS=(/etc/mkinitcpio.conf /etc/mkinitcpio.conf.d /etc/mkinitcpio.d "$CMDLINE" /etc/crypttab.initramfs
    /etc/plymouth /usr/share/plymouth/themes)
BOOT_INPUTS_STAMP="$SYSTEM_STATE/boot-inputs"

esp_supported() {
    if [[ ! -d /sys/firmware/efi ]]; then
        echo "boot: not UEFI (no /sys/firmware/efi), only the EFI layout is supported" >&2
        return 1
    fi
    if [[ "$(stat -f -c %T "$ESP")" != msdos ]]; then
        echo "boot: $ESP is not the FAT ESP, only archinstall's ESP-at-/boot layout is supported" >&2
        return 1
    fi
    if [[ ! -f "$ESP/vmlinuz-linux-lts" ]]; then
        echo "boot: linux-lts not installed, no fallback kernel when linux breaks" >&2
    fi
}

# enable_ukis: each kernel preset builds one uki, its cmdline embedded from $CMDLINE alone; systemd-boot finds it in
# $UKI_DIR without an entry, sbctl signs it. bootstrap.sh writes the same preset for the stage boots
enable_ukis() {
    local preset pkgbase want
    kernel_cmdline_set
    # nothing adds root arguments at boot any more
    if ! grep -qE '(^| )root=' "$CMDLINE" || { [[ "$(findmnt -no FSROOT /)" != / ]] && ! grep -q 'subvol=' "$CMDLINE"; }; then
        echo "boot: $CMDLINE lacks root= or the root subvol, not switching to ukis" >&2
        return 1
    fi
    for preset in /etc/mkinitcpio.d/*.preset; do
        [[ -f "$preset" ]] || continue
        pkgbase=$(basename "$preset" .preset)
        want=$(sed -e "s/^PRESETS=.*/PRESETS=('default')/" -e '/^#\?default_\(image\|uki\|cmdline\)=/d' "$preset"
            printf 'default_uki="%s"\ndefault_cmdline="%s"\n' "$UKI_DIR/arch-$pkgbase.efi" "$CMDLINE")
        [[ "$want" == "$(<"$preset")" ]] && continue
        [[ -e "$preset.arch-dotfiles-backup" ]] || install -m644 "$preset" "$preset.arch-dotfiles-backup"
        echo "$want" | install -m644 /dev/stdin "$preset"
        # a kernel installed during the stage chain (linux-lts) built a plain image, with the stage keyfile in it; nothing boots it
        rm -f "$ESP/initramfs-$pkgbase.img" "$ESP/initramfs-$pkgbase-fallback.img"
    done
}

# kernel_cmdline_set <token>...: each token replaces the tokens of its key (text before the first =) in $CMDLINE
kernel_cmdline_set() {
    local file=$CMDLINE token word words=() kept=()
    if [[ ! -f "$file" ]]; then
        tr ' ' '\n' </proc/cmdline | grep -vE '^(BOOT_IMAGE|initrd)=' | paste -sd' ' | install -Dm644 /dev/stdin "$file"
    fi
    [[ -e "$file.arch-dotfiles-backup" ]] || install -m644 "$file" "$file.arch-dotfiles-backup"
    read -ra words <"$file"
    for token in "$@"; do
        kept=()
        for word in "${words[@]}"; do
            [[ "${word%%=*}" == "${token%%=*}" && "$word" != "$token" ]] || kept+=("$word")
        done
        words=("${kept[@]}")
        [[ " ${words[*]} " == *" $token "* ]] || words+=("$token")
    done
    # the ukis pick it up at system-apply's boot barrier
    [[ "${words[*]}" == "$(<"$file")" ]] || echo "${words[*]}" | install -m644 /dev/stdin "$file"
}

# kernel_cmdline_unset <key>: drops every token of that key from $CMDLINE
kernel_cmdline_unset() {
    local file=$CMDLINE word words=() kept=()
    [[ -f "$file" ]] || return 0
    [[ -e "$file.arch-dotfiles-backup" ]] || install -m644 "$file" "$file.arch-dotfiles-backup"
    read -ra words <"$file"
    for word in "${words[@]}"; do
        [[ "${word%%=*}" == "$1" ]] || kept+=("$word")
    done
    [[ "${kept[*]}" == "$(<"$file")" ]] || echo "${kept[*]}" | install -m644 /dev/stdin "$file"
}

# sbctl_ready: keys exist, so boot files get signed; before configs/base/boot/sbctl ran there is nothing to sign with
sbctl_ready() {
    command -v sbctl >/dev/null 2>&1 && sbctl status | grep -qE 'Owner GUID'
}

sbctl_sign() {
    sbctl_ready || return 0
    local f
    for f in "$@"; do
        if [[ -f "$f" ]]; then
            sbctl sign -s "$f"
        fi
    done
}

# boot_commit: the boot barrier, one uki rebuild for every change of the run, then every boot file signed and verified
boot_commit() {
    local inputs preset unsigned
    # wsl: windows boots its own kernel, there is no initramfs or bootloader here
    command -v mkinitcpio >/dev/null 2>&1 || return 0
    # inputs this machine lacks (no plymouth, no crypttab.initramfs) hash as absent
    inputs=$(find "${BOOT_INPUTS[@]}" -type f -printf '%m %p\n' -exec sha256sum {} + 2>/dev/null | sha256sum)
    if [[ "$inputs" != "$(cat "$BOOT_INPUTS_STAMP" 2>/dev/null)" ]]; then
        mkinitcpio -P || return 1
        mkdir -p "${BOOT_INPUTS_STAMP%/*}"
        echo "$inputs" >"$BOOT_INPUTS_STAMP"
    fi
    sbctl_ready || return 0
    # sign -s lists each uki in sbctl's database, so sign-all and sbctl's pacman hook re-sign it after every kernel upgrade
    for preset in /etc/mkinitcpio.d/*.preset; do
        sbctl_sign "$UKI_DIR/arch-$(basename "$preset" .preset).efi"
    done
    # bootctl and systemd-boot-update.service copy the .signed loader onto the esp, so a systemd upgrade never lands
    # unsigned there: sbctl's pacman hook re-signs it (usr/lib/**/efi/*.efi*) in the same transaction
    sbctl sign -s -o "$SDBOOT_EFI.signed" "$SDBOOT_EFI" || return 1
    # the copies on the esp as they are now, from bootstrap's bootctl install or a copy before the .signed existed
    sbctl_sign "${SDBOOT_ESP_FILES[@]}"
    sbctl sign-all || return 1
    # the plain kernels stay unsigned: a type #1 entry on the unverified esp could boot a signed one with any cmdline and initrd
    unsigned=$(sbctl verify | grep 'is not signed' | grep -v "$ESP/vmlinuz-")
    if [[ -n "$unsigned" ]]; then
        echo "boot: unsigned with secure boot keys enrolled, the next boot may fail: $unsigned" >&2
        return 1
    fi
}

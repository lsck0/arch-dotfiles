#!/usr/bin/env bash

if ! command -v sbctl >/dev/null 2>&1; then
    exit 0
fi

set -ex

BOOT_STATE="$HOME/projects/arch-dotfiles/boot.conf"
if [[ ! -f "$BOOT_STATE" ]] || ! grep -qx sbctl "$BOOT_STATE"; then
    exit 0
fi

if [[ ! -d /sys/firmware/efi ]]; then
    echo "sbctl: not UEFI (no /sys/firmware/efi) — Secure Boot N/A on this system" >&2
    exit 0
fi

need_sign=true
if sbctl status 2>/dev/null | grep -qE 'Secure Boot:\s+Enabled'; then
    need_sign=false
    echo "sbctl: Secure Boot already enabled" >&2
fi

# SIGN EVERY UNSIGNED BOOT FILE, AND ADD IT TO SBCTL'S DATABASE.
sign_unsigned_boot_files() {
    local out paths=() p signed=0

    out="$(sudo sbctl verify 2>/dev/null || true)"
    mapfile -t paths < <(printf '%s\n' "$out" \
        | sed -n 's|^[^/]*\(/.*\) is not signed$|\1|p')

    # verify only walks the ESP.
    local cand
    for cand in \
        /boot/vmlinuz-linux /boot/vmlinuz-linux-lts /boot/vmlinuz-linux-zen \
        /boot/EFI/BOOT/BOOTX64.EFI \
        /boot/EFI/Linux/*.efi \
        /boot/EFI/systemd/systemd-bootx64.efi \
        /boot/efi/EFI/BOOT/BOOTX64.EFI \
        /boot/efi/EFI/systemd/systemd-bootx64.efi \
        /boot/limine/limine_x64.efi \
        /boot/efi/limine/limine_x64.efi \
        /boot/efi/EFI/Limine/limine_x64.efi; do
        [[ -f "$cand" ]] || continue
        sudo sbctl verify "$cand" 2>/dev/null | grep -q 'is signed' && continue
        paths+=("$cand")
    done

    if [[ ${#paths[@]} -eq 0 ]]; then
        echo "sbctl: no unsigned boot files found" >&2
        return 0
    fi

    for p in "${paths[@]}"; do
        echo "sbctl: signing $p" >&2
        sudo sbctl sign -s "$p"
        signed=$(( signed + 1 ))
    done

    # Re-sign anything already in the database that verify did not list
    sudo sbctl sign-all

    echo "sbctl: signed and registered $signed boot file(s)" >&2
}

if [[ "$need_sign" == "true" ]]; then
    st="$(sbctl status 2>/dev/null || true)"
    if [[ -z "$st" ]]; then
        echo "sbctl: cannot read firmware status" >&2
        exit 0
    fi
    if ! echo "$st" | grep -qE 'Setup Mode:\s+Enabled'; then
        echo "sbctl: firmware not in Setup Mode and SB not enabled." >&2
        echo "sbctl: enable Setup Mode / Secure Boot in firmware, then rerun install.sh." >&2
        exit 0
    fi

    # Keys present?
    if ! echo "$st" | grep -qE 'Owner GUID'; then
        echo "sbctl: creating keys" >&2
        sudo sbctl create-keys
    fi

    # SIGN BEFORE ENROLLING.
    echo "sbctl: signing boot files before enrollment" >&2
    sign_unsigned_boot_files

    if ! sudo sbctl list-enrolled-keys 2>/dev/null | grep -q .; then
        echo "sbctl: enrolling keys (incl. Microsoft DB for dual-boot compat)" >&2
        sudo sbctl enroll-keys -m
    fi
    echo "sbctl: keys created/enrolled and boot files signed. Enable Secure Boot in firmware, reboot, then rerun install.sh." >&2
    echo "sbctl: verify with 'sbctl verify' BEFORE rebooting with Secure Boot on." >&2
    exit 0
fi

echo "sbctl: signing ESP boot files" >&2
sign_unsigned_boot_files

# sbctl-mkinitcpio hook auto-signs kernels/UKIs at initcpio build time
if command -v sbctl-mkinitcpio >/dev/null 2>&1; then
    sudo systemctl enable sbctl-mkinitcpio.path 2>/dev/null || true
    sudo systemctl enable sbctl-mkinitcpio.service 2>/dev/null || true
fi

echo "sbctl: signing complete. Run 'sbctl verify' to confirm." >&2

#!/usr/bin/env bash

set -e

if [[ ! -d /sys/firmware/efi ]]; then
    echo "sbctl: not UEFI (no /sys/firmware/efi), Secure Boot N/A on this system" >&2
    exit 0
fi

need_sign=true
if sbctl status | grep -qE 'Secure Boot:\s+(\S+\s+)?Enabled'; then
    need_sign=false
    echo "sbctl: Secure Boot already enabled" >&2
fi

sign_unsigned_boot_files() {
    local out paths=() p signed=0

    out="$(sudo sbctl verify)"
    mapfile -t paths < <(printf '%s\n' "$out" \
        | sed -n 's|^[^/]*\(/.*\) is not signed$|\1|p')

    # sbctl verify only walks the esp
    local cand
    for cand in \
        /boot/vmlinuz-linux /boot/vmlinuz-linux-lts /boot/vmlinuz-linux-zen \
        /boot/EFI/BOOT/BOOTX64.EFI \
        /boot/EFI/GRUB/grubx64.efi \
        /boot/EFI/Linux/*.efi \
        /boot/EFI/systemd/systemd-bootx64.efi \
        /boot/efi/EFI/BOOT/BOOTX64.EFI \
        /boot/efi/EFI/systemd/systemd-bootx64.efi; do
        [[ -f "$cand" ]] || continue
        sudo sbctl verify "$cand" | grep -q 'is signed' && continue
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

    # re-sign database entries verify did not list
    sudo sbctl sign-all

    echo "sbctl: signed and registered $signed boot file(s)" >&2
}

if [[ "$need_sign" == "true" ]]; then
    st="$(sbctl status)"
    if ! echo "$st" | grep -qE 'Setup Mode:\s+(\S+\s+)?Enabled'; then
        echo "sbctl: firmware not in Setup Mode and SB not enabled." >&2
        echo "sbctl: enable Setup Mode / Secure Boot in firmware, then rerun config.sh." >&2
        exit 0
    fi

    if ! echo "$st" | grep -qE 'Owner GUID'; then
        echo "sbctl: creating keys" >&2
        sudo sbctl create-keys
    fi

    # sign before enrolling
    echo "sbctl: signing boot files before enrollment" >&2
    sign_unsigned_boot_files

    if ! sudo sbctl list-enrolled-keys | grep -qvE '^\S+:\s*$'; then
        # own keys only, no -m: one esp, no dual boot, and fwupd signs its capsule efi with these keys;
        # takes effect only on a fresh enroll, so a machine already carrying ms keys must clear sb in firmware and rerun
        echo "sbctl: enrolling own keys only (clear Secure Boot keys in firmware to re-enroll without Microsoft's)" >&2
        sudo sbctl enroll-keys
    fi
    echo "sbctl: keys created/enrolled and boot files signed. Enable Secure Boot in firmware, reboot, then rerun config.sh." >&2
    echo "sbctl: verify with 'sbctl verify' BEFORE rebooting with Secure Boot on." >&2
    exit 0
fi

echo "sbctl: signing ESP boot files" >&2
sign_unsigned_boot_files

echo "sbctl: signing complete. Run 'sbctl verify' to confirm." >&2

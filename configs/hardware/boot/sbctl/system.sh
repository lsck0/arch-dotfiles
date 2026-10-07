#!/usr/bin/env bash

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

    out="$(sbctl verify)"
    # the plain kernels stay unsigned: grub.cfg could chainload a signed one with any cmdline and initrd
    mapfile -t paths < <(printf '%s\n' "$out" \
        | sed -n 's|^[^/]*\(/.*\) is not signed$|\1|p' | grep -v '^/boot/vmlinuz-')

    # sbctl verify only walks the esp
    local cand
    for cand in \
        /boot/EFI/BOOT/BOOTX64.EFI \
        /boot/EFI/GRUB/grubx64.efi \
        /boot/EFI/Linux/*.efi \
        /boot/EFI/systemd/systemd-bootx64.efi \
        /boot/efi/EFI/BOOT/BOOTX64.EFI \
        /boot/efi/EFI/systemd/systemd-bootx64.efi; do
        [[ -f "$cand" ]] || continue
        sbctl verify "$cand" | grep -q 'is signed' && continue
        paths+=("$cand")
    done

    if [[ ${#paths[@]} -eq 0 ]]; then
        echo "sbctl: no unsigned boot files found" >&2
        return 0
    fi

    for p in "${paths[@]}"; do
        echo "sbctl: signing $p" >&2
        sbctl sign -s "$p"
        signed=$(( signed + 1 ))
    done

    # re-sign database entries verify did not list
    sbctl sign-all

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
        sbctl create-keys
    fi

    # sign before enrolling
    echo "sbctl: signing boot files before enrollment" >&2
    sign_unsigned_boot_files

    if ! sbctl list-enrolled-keys | grep -qvE '^\S+:\s*$'; then
        # the plain kernels are never signed, so enforcing secure boot under a grub.cfg that still boots one leaves nothing bootable
        if grep -qE '^\s*linux\s+/vmlinuz-' /boot/grub/grub.cfg 2>/dev/null; then
            echo "sbctl: grub.cfg still boots a plain kernel, not enrolling keys until configs/hardware/boot/grub succeeds" >&2
            exit 1
        fi
        # own keys only where the platform says so (SECURE_BOOT_OWN_KEYS): one esp, no dual boot, and fwupd signs its capsule
        # efi with these keys; takes effect only on a fresh enroll, so a machine already carrying ms keys must clear sb in firmware and rerun
        if [[ -n "$SECURE_BOOT_OWN_KEYS" ]]; then
            echo "sbctl: enrolling own keys only (clear Secure Boot keys in firmware to re-enroll without Microsoft's)" >&2
            sbctl enroll-keys
        else
            # anyone else's machine may still boot windows, other loaders or option roms signed by microsoft
            echo "sbctl: enrolling own keys plus Microsoft's" >&2
            sbctl enroll-keys -m
        fi
    fi
    echo "sbctl: keys created/enrolled and boot files signed. Enable Secure Boot in firmware, reboot, then rerun config.sh." >&2
    echo "sbctl: verify with 'sbctl verify' BEFORE rebooting with Secure Boot on." >&2
    exit 0
fi

echo "sbctl: signing ESP boot files" >&2
sign_unsigned_boot_files

echo "sbctl: signing complete. Run 'sbctl verify' to confirm." >&2

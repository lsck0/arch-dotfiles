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
    # the plain kernels stay unsigned: a type #1 entry on the unverified esp could boot a signed one with any cmdline and initrd
    mapfile -t paths < <(printf '%s\n' "$out" \
        | sed -n 's|^[^/]*\(/.*\) is not signed$|\1|p' | grep -v '^/boot/vmlinuz-')

    # sbctl verify only walks the esp
    local cand
    for cand in \
        /boot/EFI/BOOT/BOOTX64.EFI \
        /boot/EFI/Linux/*.efi \
        /boot/EFI/systemd/systemd-bootx64.efi \
        /boot/efi/EFI/BOOT/BOOTX64.EFI \
        /boot/efi/EFI/systemd/systemd-bootx64.efi; do
        [[ -f "$cand" ]] || continue
        # verify's esp walk may already have listed it
        [[ " ${paths[*]} " == *" $cand "* ]] && continue
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

    # efivarfs marks the existing secure boot variables immutable, so enroll-keys fails with "File is immutable" on
    # KEK/db and never writes PK; clear the flag on exactly these, the firmware still guards them outside setup mode
    for var in /sys/firmware/efi/efivars/{PK,KEK,db,dbx}-*; do
        [[ -e "$var" ]] && chattr -i "$var"
    done

    # setup mode is the authoritative "no PK, must enroll" signal; leftover KEK/db vendor certs can still be present, so
    # never gate the enroll on list-enrolled-keys being empty — that skips the one write that leaves setup mode
    if [[ -n "$SECURE_BOOT_OWN_KEYS" && -r /sys/kernel/security/tpm0/binary_bios_measurements ]]; then
        # sbctl refuses a plain enroll when the event log shows an option rom (a dgpu's gop): -t puts the measured
        # hashes in db beside our keys, so they keep loading without the microsoft ca; a gpu swap or vbios update
        # changes them and needs a re-enroll
        echo "sbctl: enrolling own keys plus the TPM event log's option rom hashes, no Microsoft keys" >&2
        echo "sbctl: (clear Secure Boot keys in firmware to re-enroll a machine that already carries Microsoft's)" >&2
        # a machine without option roms (integrated gpu) has no hashes to add and -t refuses ("could not find any OpROM
        # entries"); nothing then needs microsoft's ca, so own keys alone, which is what SECURE_BOOT_OWN_KEYS asks for
        if ! out=$(sbctl enroll-keys -t 2>&1); then
            echo "$out" >&2
            if grep -q 'could not find any OpROM entries' <<<"$out"; then
                echo "sbctl: no option roms in the TPM event log, enrolling own keys only" >&2
                sbctl enroll-keys
            fi
        fi
    elif [[ -n "$SECURE_BOOT_OWN_KEYS" ]]; then
        # without an event log sbctl cannot tell whether an option rom needs microsoft's ca; forcing could brick
        echo "sbctl: !!! SECURE_BOOT_OWN_KEYS set but no TPM event log to read option rom hashes from" >&2
        echo "sbctl: !!! falling back to own keys PLUS Microsoft's, the Microsoft CA stays trusted in db" >&2
        sbctl enroll-keys -m
    else
        # anyone else's machine may still boot windows, other loaders or option roms signed by microsoft
        echo "sbctl: enrolling own keys plus Microsoft's" >&2
        sbctl enroll-keys -m
    fi
    if sbctl status | grep -qE 'Setup Mode:\s+(\S+\s+)?Enabled'; then
        echo "sbctl: !!! enroll-keys ran but firmware still in Setup Mode; PK not written (enroll failed or efivars locked)" >&2
        exit 1
    fi
    echo "sbctl: keys created/enrolled and boot files signed. Enable Secure Boot in firmware, reboot, then rerun config.sh." >&2
    echo "sbctl: verify with 'sbctl verify' BEFORE rebooting with Secure Boot on." >&2
    exit 0
fi

echo "sbctl: signing ESP boot files" >&2
sign_unsigned_boot_files

echo "sbctl: signing complete. Run 'sbctl verify' to confirm." >&2

#!/usr/bin/env bash
# sbctl / Secure Boot provisioning.
# Idempotent. Operates only on UEFI systems with sbctl installed. Does NOT
# create an ESP or convert MBR→GPT — that is a manual step; see README
# §Boot disk security + BOOT.md §Execution sequence.
set -euo pipefail

BOOT_STATE="$HOME/projects/arch-dotfiles/boot.conf"
if [[ ! -f "$BOOT_STATE" ]] || ! grep -qx sbctl "$BOOT_STATE"; then
    exit 0
fi

if [[ ! -d /sys/firmware/efi ]]; then
    echo "sbctl: not UEFI (no /sys/firmware/efi) — Secure Boot N/A on this system" >&2
    exit 0
fi
if ! command -v sbctl >/dev/null 2>&1; then
    echo "sbctl: sbctl not installed — nothing to do (should be pulled in by install.sh base group)" >&2
    exit 0
fi

need_sign=true
if sbctl status 2>/dev/null | grep -qE 'Secure Boot:\s+Enabled'; then
    need_sign=false
    echo "sbctl: Secure Boot already enabled" >&2
fi

# SIGN EVERY UNSIGNED BOOT FILE, AND ADD IT TO SBCTL'S DATABASE.
#
# `sbctl sign-all` is NOT enough on its own, and this is the trap that made an
# earlier version of this script claim success while signing nothing at all:
# sign-all iterates sbctl's own file database (/var/lib/sbctl/files.json),
# which starts EMPTY on a fresh install. Only `sbctl sign -s <path>` adds an
# entry. So the database has to be populated from the real ESP first, and
# `sbctl verify` is what enumerates it.
#
# verify prints one line per file, `<glyph> <path> is [not] signed`. The path
# is taken as everything from the first `/` up to ` is not signed` — the
# previous version used sed's `&`, which expands to the WHOLE matched line, so
# it fed the glyph and the status text to `sbctl sign` as part of the filename.
sign_unsigned_boot_files() {
    local out paths=() p signed=0

    out="$(sudo sbctl verify 2>/dev/null || true)"
    mapfile -t paths < <(printf '%s\n' "$out" \
        | sed -n 's|^[^/]*\(/.*\) is not signed$|\1|p')

    # verify only walks the ESP. A kernel or UKI outside it (or an ESP sbctl
    # cannot find yet) still has to be registered, so known locations are
    # checked explicitly rather than trusted to show up above.
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

    # NOT silenced, and NOT `|| true`. This is the step that decides whether the
    # machine boots once Secure Boot is switched on; a failure here has to be
    # visible and has to propagate to install.sh's FAILURES list.
    for p in "${paths[@]}"; do
        echo "sbctl: signing $p" >&2
        sudo sbctl sign -s "$p"
        signed=$(( signed + 1 ))
    done

    # Re-sign anything already in the database that verify did not list, now
    # that the database is actually populated.
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
        echo "sbctl: see README §Boot disk security." >&2
        exit 0
    fi

    # Keys present?
    if ! echo "$st" | grep -qE 'Owner GUID'; then
        echo "sbctl: creating keys" >&2
        sudo sbctl create-keys
    fi

    # SIGN BEFORE ENROLLING. Signing needs the keys to exist, not to be enrolled,
    # and the window between "keys enrolled" and "boot chain signed" is a window
    # in which switching Secure Boot on in firmware leaves the machine unable to
    # boot anything. Closing it costs one command in a different order.
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

# SB is on — sign the ESP boot chain. Sign any unsigned ESP executables and
# the Limine UEFI binary if present (Limine + SB is reportedly finicky; UKIs
# signed by sbctl are the robust path — see BOOT.md).
echo "sbctl: signing ESP boot files" >&2

# Same helper as the pre-enrollment path: enumerate what is unsigned, register
# each file with `sbctl sign -s` so it stays signed on future kernel installs,
# then sign-all for anything already in the database. The Limine binary and the
# kernel images are in the helper's explicit candidate list, so there is no
# second loop here.
sign_unsigned_boot_files

# sbctl-mkinitcpio hook auto-signs kernels/UKIs at initcpio build time; ensure
# it is enabled so future kernel installs stay signed under SB.
if command -v sbctl-mkinitcpio >/dev/null 2>&1; then
    sudo systemctl enable sbctl-mkinitcpio.path 2>/dev/null || true
    sudo systemctl enable sbctl-mkinitcpio.service 2>/dev/null || true
fi

echo "sbctl: signing complete. Run 'sbctl verify' to confirm." >&2

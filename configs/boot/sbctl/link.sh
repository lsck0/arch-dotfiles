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

    # Keys present + enrolled?
    if ! echo "$st" | grep -qE 'Owner GUID'; then
        echo "sbctl: creating keys" >&2
        sudo sbctl create-keys
    fi
    if ! sudo sbctl list-enrolled-keys 2>/dev/null | grep -q .; then
        echo "sbctl: enrolling keys (incl. Microsoft DB for dual-boot compat)" >&2
        sudo sbctl enroll-keys -m
    fi
    echo "sbctl: keys created/enrolled. Enable Secure Boot in firmware, reboot, then rerun install.sh to sign boot files." >&2
    exit 0
fi

# SB is on — sign the ESP boot chain. Sign any unsigned ESP executables and
# the Limine UEFI binary if present (Limine + SB is reportedly finicky; UKIs
# signed by sbctl are the robust path — see BOOT.md).
echo "sbctl: signing ESP boot files" >&2

# All enrolled/required files that are unsigned.
if sudo sbctl verify 2>/dev/null | grep -q 'not signed'; then
    sudo sbctl verify 2>/dev/null | sed -n 's/.*is not signed$/sbctl sign -s "&"/p' \
        | while IFS= read -r cmd; do sudo bash -lc "$cmd" 2>/dev/null || true; done
fi

# Limine UEFI binary (if Limine is the bootloader).
for cand in \
    /boot/limine/limine_x64.efi \
    /boot/efi/limine/limine_x64.efi \
    /boot/efi/EFI/Limine/limine_x64.efi; do
    if [[ -f "$cand" ]]; then
        if ! sudo sbctl verify "$cand" 2>/dev/null | grep -q 'OK'; then
            echo "sbctl: signing $cand" >&2
            sudo sbctl sign -s "$cand" 2>/dev/null || true
        fi
    fi
done

# sbctl-mkinitcpio hook auto-signs kernels/UKIs at initcpio build time; ensure
# it is enabled so future kernel installs stay signed under SB.
if command -v sbctl-mkinitcpio >/dev/null 2>&1; then
    sudo systemctl enable sbctl-mkinitcpio.path 2>/dev/null || true
    sudo systemctl enable sbctl-mkinitcpio.service 2>/dev/null || true
fi

echo "sbctl: signing complete. Run 'sbctl verify' to confirm." >&2

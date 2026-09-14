#!/usr/bin/env bash
# LUKS / dm-crypt provisioning.
# Idempotent. Detects existing LUKS-encrypted devices and configures
# /etc/crypttab options + ensures the mkinitcpio encrypt hook is present.
# Does NOT migrate a non-encrypted root into LUKS — that is a manual,
# point-of-no-return step (fresh install or btrfs send/receive from backup);
# see README §Boot disk security + BOOT.md §Execution sequence.
set -euo pipefail

BOOT_STATE="$HOME/projects/arch-dotfiles/boot.conf"
if [[ ! -f "$BOOT_STATE" ]] || ! grep -qx luks "$BOOT_STATE"; then
    exit 0
fi

MARKER="# MARKER:arch-dotfiles/boot/luks"
CRYPTTAB="/etc/crypttab"

# Detect LUKS partition backends (not the mapped devices themselves).
mapfile -t LUKS_PARTS < <(lsblk -n -o NAME,UUID,FSTYPE,TYPE 2>/dev/null \
    | awk '$3 == "crypto_LUKS" && $4 == "part" {print $1, $2}' || true)

if [[ ${#LUKS_PARTS[@]} -eq 0 ]]; then
    echo "luks: no LUKS-encrypted partitions detected — nothing to configure" >&2
    exit 0
fi

# Ensure crypttab header + marker exist, back up a pre-existing live file.
sudo mkdir -p "$(dirname "$CRYPTTAB")"
if [[ -f "$CRYPTTAB" ]]; then
    if ! sudo grep -qF "$MARKER" "$CRYPTTAB" 2>/dev/null; then
        sudo install -m644 "$CRYPTTAB" "${CRYPTTAB}.arch-dotfiles-backup" 2>/dev/null || true
    fi
fi
if [[ ! -f "$CRYPTTAB" ]]; then
    sudo install -m644 "$(dirname "$0")/crypttab" "$CRYPTTAB"
else
    # Strip any auto-appended entries from a prior run so we can rewrite cleanly.
    if sudo grep -qF "$MARKER" "$CRYPTTAB" 2>/dev/null; then
        sudo sed -i "/^$MARKER$/,\$d" "$CRYPTTAB"
    fi
    sudo sed -i -e '$a\' "$(dirname "$0")/crypttab" "$CRYPTTAB"
fi

# Append one entry per LUKS partition, idempotent per device name.
for entry in "${LUKS_PARTS[@]}"; do
    part="${entry%% *}"
    uuid="${entry##* }"
    if sudo grep -qE "^${part}\s" "$CRYPTTAB" 2>/dev/null; then
        continue
    fi
    printf '%s\tUUID=%s\tnone\tluks,discard,perf-no-read-workqueue,perf-no-write-workqueue\n' \
        "$part" "$uuid" | sudo tee -a "$CRYPTTAB" >/dev/null
done
echo "$MARKER" | sudo tee -a "$CRYPTTAB" >/dev/null

# mkinitcpio: ensure the encrypt hook is present before filesystems.
CONF="/etc/mkinitcpio.conf"
if [[ -f "$CONF" ]]; then
    if grep -qE 'HOOKS=\(.*\bencrypt\b' "$CONF"; then
        echo "luks: encrypt hook already in mkinitcpio.conf" >&2
    elif grep -qE 'HOOKS=\(.*\bsd-encrypt\b' "$CONF"; then
        echo "luks: sd-encrypt hook already in mkinitcpio.conf" >&2
    elif grep -qE 'HOOKS=\(.*\bsystemd\b' "$CONF"; then
        echo "luks: systemd hook present — encrypt handled by systemd-cryptsetup in initrd" >&2
    else
        echo "luks: adding encrypt hook before filesystems in mkinitcpio.conf" >&2
        sudo python - <<'PY'
from pathlib import Path
p = Path("/etc/mkinitcpio.conf")
s = p.read_text()
if "HOOKS=(" in s:
    i = s.index("HOOKS=(")
    j = s.index(")", i) + 1
    block = s[i:j]
    if "encrypt" not in block and "systemd" not in block:
        s = s[:i] + block.replace("filesystems", "encrypt filesystems", 1) + s[j:]
        p.write_text(s)
PY
    fi
fi

# Rebuild initramfs so crypttab-backed devices are recognized at boot.
if command -v mkinitcpio >/dev/null 2>&1; then
    sudo mkinitcpio -P 2>/dev/null || true
fi

echo "luks: crypttab configured for ${#LUKS_PARTS[@]} LUKS partition(s)" >&2

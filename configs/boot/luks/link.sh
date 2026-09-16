#!/usr/bin/env bash

set -ex

BOOT_STATE="$HOME/projects/arch-dotfiles/boot.conf"
if [[ ! -f "$BOOT_STATE" ]] || ! grep -qx luks "$BOOT_STATE"; then
    exit 0
fi

MARKER="# MARKER:arch-dotfiles/boot/luks"
CRYPTTAB="/etc/crypttab"

# Detect LUKS partition backends
mapfile -t LUKS_PARTS < <(lsblk -ln -o NAME,UUID,FSTYPE,TYPE 2>/dev/null \
    | awk '$3 == "crypto_LUKS" && $4 == "part" {print $1, $2}' || true)

if [[ ${#LUKS_PARTS[@]} -eq 0 ]]; then
    echo "luks: no LUKS-encrypted partitions detected — nothing to configure" >&2
    exit 0
fi

# THE ROOT DEVICE MUST NOT GO IN CRYPTTAB.
ROOT_SRC="$(findmnt -n -o SOURCE / 2>/dev/null || true)"
ROOT_SRC="${ROOT_SRC%%[*}"
ROOT_BACKING=""
if [[ "$ROOT_SRC" == /dev/mapper/* ]]; then
    ROOT_BACKING="$(lsblk -lnso NAME,TYPE "$ROOT_SRC" 2>/dev/null | awk '$2 == "part" {print $1; exit}' || true)"
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
    sudo sed -i -e '$a\' "$CRYPTTAB"
fi

# Append one entry per non-root LUKS partition, idempotent per mapper name.
added=0
for entry in "${LUKS_PARTS[@]}"; do
    part="${entry%% *}"
    uuid="${entry##* }"
    [[ -z "$uuid" || "$uuid" == "$part" ]] && continue
    if [[ -n "$ROOT_BACKING" && "$part" == "$ROOT_BACKING" ]]; then
        continue
    fi
    name="luks-${uuid}"
    if sudo grep -qE "^${name}\s" "$CRYPTTAB" 2>/dev/null; then
        continue
    fi
    printf '%s\tUUID=%s\tnone\tluks,discard,perf-no-read-workqueue,perf-no-write-workqueue\n' \
        "$name" "$uuid" | sudo tee -a "$CRYPTTAB" >/dev/null
    added=$(( added + 1 ))
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
        echo "luks: systemd hook present, encrypt handled by systemd-cryptsetup in initrd" >&2
    else
        echo "luks: adding encrypt hook before filesystems in mkinitcpio.conf" >&2
        if [[ ! -e "${CONF}.arch-dotfiles-backup" ]]; then
            sudo install -Dm644 "$CONF" "${CONF}.arch-dotfiles-backup"
        fi
        sudo python - <<'PY'
import sys
from pathlib import Path
p = Path("/etc/mkinitcpio.conf")
s = p.read_text()
if "HOOKS=(" not in s:
    sys.exit("luks: no HOOKS=( line in mkinitcpio.conf — refusing to guess")
i = s.index("HOOKS=(")
j = s.index(")", i) + 1
block = s[i:j]
if "encrypt" in block or "systemd" in block:
    sys.exit(0)
if "filesystems" not in block:
    sys.exit("luks: HOOKS has no `filesystems` hook, refusing to place `encrypt`")
if "block" not in block:
    sys.exit("luks: HOOKS has no `block` hook, `encrypt` would have no device")
if "keyboard" not in block:
    sys.exit("luks: HOOKS has no `keyboard` hook, passphrase entry would be impossible")
p.write_text(s[:i] + block.replace("filesystems", "encrypt filesystems", 1) + s[j:])
PY
    fi
fi

# Rebuild initramfs so crypttab-backed devices are recognized at boot.
if command -v mkinitcpio >/dev/null 2>&1; then
    sudo mkinitcpio -P
fi

echo "luks: crypttab configured, $added non-root LUKS volume(s) added" >&2

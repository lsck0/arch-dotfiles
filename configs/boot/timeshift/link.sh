#!/usr/bin/env bash

if ! command -v timeshift >/dev/null 2>&1; then
    exit 0
fi

set -ex

BOOT_STATE="$HOME/projects/arch-dotfiles/boot.conf"
if [[ ! -f "$BOOT_STATE" ]] || ! grep -qx timeshift "$BOOT_STATE"; then
    exit 0
fi

ROOT_SOURCE="$(findmnt -n -o SOURCE / 2>/dev/null || true)"
ROOT_FSTYPE="$(findmnt -n -o FSTYPE / 2>/dev/null || true)"
ROOT_OPTS="$(findmnt -n -o OPTIONS / 2>/dev/null || true)"
ROOT_SUBDIR="$(findmnt -n -o FSROOT / 2>/dev/null || true)"

if [[ "$ROOT_FSTYPE" != "btrfs" ]]; then
    echo "timeshift: root fs is $ROOT_FSTYPE, not btrfs — btrfs-mode N/A" >&2
    exit 0
fi

# btrfs-mode timeshift requires root mounted from a subvolume named '@' 
if [[ "$ROOT_OPTS" =~ subvolid=5 ]] || [[ "$ROOT_SUBDIR" == "/" || "$ROOT_SUBDIR" == "" ]]; then
    echo "timeshift: root is top-level btrfs subvol (subvolid=5)" >&2
    echo "timeshift: btrfs-mode needs a named subvol (e.g. '@') as root." >&2
    exit 0
fi

sudo mkdir -p /etc/timeshift

DEF='"_managed_by": "arch-dotfiles/boot/timeshift"'
if [[ -f /etc/timeshift/timeshift.json ]]; then
    if ! sudo grep -qF "$DEF" /etc/timeshift/timeshift.json 2>/dev/null; then
        sudo install -m644 /etc/timeshift/timeshift.json \
            /etc/timeshift/timeshift.json.arch-dotfiles-backup 2>/dev/null || true
    fi
fi

ROOT_UUID="$(lsblk -no UUID "$ROOT_SOURCE" 2>/dev/null || true)"
if [[ -z "$ROOT_UUID" ]]; then
    echo "timeshift: cannot determine root UUID for $ROOT_SOURCE" >&2
    exit 1
fi

sed "s|PLACEHOLDER_ROOT_UUID|$ROOT_UUID|" \
    "$(dirname "$0")/timeshift.json" | sudo tee /etc/timeshift/timeshift.json >/dev/null

# timeshift hard-depends on cronie
if systemctl list-unit-files --no-legend cronie.service 2>/dev/null | grep -q .; then
    sudo systemctl enable cronie.service 2>/dev/null || true
fi

echo "timeshift: btrfs-mode config written (root UUID $ROOT_UUID)" >&2

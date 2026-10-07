#!/usr/bin/env bash

CONF=/etc/timeshift/timeshift.json
MANAGED='"_managed_by": "arch-dotfiles/boot/timeshift"'

ROOT_SOURCE="$(findmnt -n -o SOURCE /)"
ROOT_FSTYPE="$(findmnt -n -o FSTYPE /)"
ROOT_OPTS="$(findmnt -n -o OPTIONS /)"
ROOT_SUBDIR="$(findmnt -n -o FSROOT /)"

if [[ "$ROOT_FSTYPE" != "btrfs" ]]; then
    echo "timeshift: root fs is $ROOT_FSTYPE, not btrfs, btrfs-mode N/A" >&2
    exit 0
fi

# btrfs mode needs root on a named subvolume like @
if [[ "$ROOT_OPTS" =~ subvolid=5 ]] || [[ "$ROOT_SUBDIR" == "/" || "$ROOT_SUBDIR" == "" ]]; then
    echo "timeshift: root is top-level btrfs subvol (subvolid=5)" >&2
    echo "timeshift: btrfs-mode needs a named subvol (e.g. '@') as root." >&2
    exit 0
fi

if [[ -f "$CONF" ]] && ! grep -qF "$MANAGED" "$CONF"; then
    install -m644 "$CONF" "$CONF.arch-dotfiles-backup"
fi

ROOT_UUID="$(findmnt -n -o UUID /)"
if [[ -z "$ROOT_UUID" ]]; then
    echo "timeshift: cannot determine root UUID for $ROOT_SOURCE" >&2
    exit 1
fi
file_render timeshift.json "$CONF" ROOT_UUID="$ROOT_UUID"

# --check takes the weekly snapshot when one is due, the timer runs it daily instead of an hourly cron daemon
unit_install timeshift-check.service timeshift-check.timer
systemctl enable --now timeshift-check.timer
timeshift --check --scripted

echo "timeshift: btrfs-mode config written (root UUID $ROOT_UUID)" >&2

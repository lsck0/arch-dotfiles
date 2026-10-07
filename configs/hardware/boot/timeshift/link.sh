#!/usr/bin/env bash

set -e

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

DEF='"_managed_by": "arch-dotfiles/boot/timeshift"'
if [[ -f /etc/timeshift/timeshift.json ]] && ! sudo grep -qF "$DEF" /etc/timeshift/timeshift.json; then
    sudo install -m644 /etc/timeshift/timeshift.json /etc/timeshift/timeshift.json.arch-dotfiles-backup
fi

ROOT_UUID="$(findmnt -n -o UUID /)"
if [[ -z "$ROOT_UUID" ]]; then
    echo "timeshift: cannot determine root UUID for $ROOT_SOURCE" >&2
    exit 1
fi

sed "s|PLACEHOLDER_ROOT_UUID|$ROOT_UUID|" "$(dirname "$0")/timeshift.json" \
    | sudo install -Dm644 /dev/stdin /etc/timeshift/timeshift.json

# --check takes the weekly snapshot when one is due, the timer runs it daily instead of an hourly cron daemon
sudo install -Dm644 "$(dirname "$0")/timeshift-check.service" /etc/systemd/system/timeshift-check.service
sudo install -Dm644 "$(dirname "$0")/timeshift-check.timer" /etc/systemd/system/timeshift-check.timer
sudo systemctl daemon-reload
sudo systemctl enable --now timeshift-check.timer
sudo timeshift --check --scripted

echo "timeshift: btrfs-mode config written (root UUID $ROOT_UUID)" >&2

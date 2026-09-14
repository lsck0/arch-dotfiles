#!/usr/bin/env bash
# timeshift btrfs-mode provisioning.
# Idempotent — safe to rerun. Skips when root is not btrfs or the subvolume
# layout is incompatible (top-level subvol as root). Does NOT migrate layout;
# see README §Boot disk security + BOOT.md for the manual conversion.
set -euo pipefail

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

# btrfs-mode timeshift requires root mounted from a subvolume named '@' (or
# another named subvol), NOT the top-level subvolume (subvolid=5, subvol=/).
if [[ "$ROOT_OPTS" =~ subvolid=5 ]] || [[ "$ROOT_SUBDIR" == "/" || "$ROOT_SUBDIR" == "" ]]; then
    echo "timeshift: root is top-level btrfs subvol (subvolid=5)" >&2
    echo "timeshift: btrfs-mode needs a named subvol (e.g. '@') as root." >&2
    echo "timeshift: conversion steps: README §Boot disk security, BOOT.md §Execution sequence." >&2
    exit 0
fi

# Layout is compatible — install config + wire the autosnap hook.
sudo mkdir -p /etc/timeshift
# "Is this file ours?" as a JSON member, not a leading `# ...` line. The comment
# form made the config invalid JSON — timeshift parses it with json-glib, which
# fails on the first character — so the backup below was comparing against a
# file timeshift itself could not read. Unknown members are ignored by the
# parser, so carrying the marker inside the object costs nothing.
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

# timeshift hard-depends on cronie for scheduled snapshots; systemd/link.sh
# already enables it, but guard here in case that didn't run.
if systemctl list-unit-files --no-legend cronie.service 2>/dev/null | grep -q .; then
    sudo systemctl enable cronie.service 2>/dev/null || true
fi

echo "timeshift: btrfs-mode config written (root UUID $ROOT_UUID)" >&2

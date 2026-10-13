#!/usr/bin/env bash

# cronie comes only as timeshift's dependency and nothing else here uses cron: timeshift-check.timer replaces its job
systemctl disable --now cronie.service 2>/dev/null || true

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

# timeshift rewrites the file with its own keys only, dropping the marker: back up the pre-dotfiles config once
if [[ -f "$CONF" && ! -e "$CONF.arch-dotfiles-backup" ]] && ! grep -qF "$MANAGED" "$CONF"; then
    install -m644 "$CONF" "$CONF.arch-dotfiles-backup"
fi

ROOT_UUID="$(findmnt -n -o UUID /)"
if [[ -z "$ROOT_UUID" ]]; then
    echo "timeshift: cannot determine root UUID for $ROOT_SOURCE" >&2
    exit 1
fi
file_render timeshift.json "$CONF" ROOT_UUID="$ROOT_UUID"

file_update timeshift-autosnap.conf /etc/timeshift-autosnap.conf || true

# --check takes the weekly snapshot when one is due, the timer runs it daily instead of an hourly cron daemon;
# timeshift writes its cron jobs whenever it saves a schedule, the service and this run remove them again
unit_install timeshift-check.service timeshift-check.timer
systemctl enable --now timeshift-check.timer
timeshift --check --scripted
rm -f /etc/cron.d/timeshift-hourly /etc/cron.d/timeshift-boot

# a restored @ boots the esp's newer kernels against its older /usr/lib/modules (ROLLBACK.md); put them back in step
if [[ "$(stat -f -c %T /boot)" == msdos ]]; then
    # vfat from the initrd, or /boot never mounts and the resync never runs; boot_commit rebuilds the ukis
    file_update esp-vfat.conf /etc/mkinitcpio.conf.d/10-esp-vfat.conf || true
    file_update kernel-resync.sh /usr/local/bin/kernel-resync 755 || true
    unit_install kernel-resync.service
    systemctl enable kernel-resync.service
fi

echo "timeshift: btrfs-mode config written (root UUID $ROOT_UUID)" >&2

#!/usr/bin/env bash
# systemd-boot boots the ukis enable_ukis sets up; system-apply's boot barrier (boot_commit) rebuilds and signs both

source "$DOTFILES/configs/base/boot/common.sh"

esp_supported || exit 0

enable_ukis

# bootstrap.sh installs it onto the esp and into the firmware's boot order
bootctl --esp-path="$ESP" is-installed >/dev/null || bootctl --esp-path="$ESP" install
# cp, not install -m: a chmod on the fmask=0077 fat esp fails
mkdir -p "$ESP/loader"
cmp -s loader.conf "$ESP/loader/loader.conf" || cp loader.conf "$ESP/loader/loader.conf"

# a systemd upgrade replaces only the package's copy, and sbctl's pacman hook re-signs its .signed (boot_commit) in the
# same transaction; this copies that onto the esp at the next boot, so an unsigned loader never lands there. a pacman
# hook running bootctl update instead would race sbctl's for the last place in hook order
systemctl enable systemd-boot-update.service

echo "systemd-boot: installed, its ukis are rebuilt and signed in system-apply's boot barrier" >&2

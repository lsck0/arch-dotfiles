#!/usr/bin/env bash
cd "$(dirname "$(readlink -f "$0")")" || exit 1

if ! command -v fwupdmgr >/dev/null 2>&1; then
    exit 0
fi

set -e

source ../boot/boot-menu/common.sh

sudo install -Dm640 fwupd.conf /etc/fwupd/fwupd.conf
sudo systemctl try-restart fwupd.service
# metadata only, updates stay manual: fwupdmgr get-updates, fwupdmgr update
sudo systemctl enable --now fwupd-refresh.timer

# capsule updates boot fwupdx64.efi; sbctl's pacman hook re-signs it on every fwupd upgrade once it is in sbctl's list
efi=/usr/lib/fwupd/efi/fwupdx64.efi
if sbctl_ready && [[ -f "$efi" ]]; then
    sudo sbctl sign -s -o "$efi.signed" "$efi"
fi

#!/usr/bin/env bash

source "$DOTFILES/configs/hardware/boot/boot-menu/common.sh"

install -Dm640 fwupd.conf /etc/fwupd/fwupd.conf
systemctl try-restart fwupd.service
# metadata only, updates stay manual: fwupdmgr get-updates, fwupdmgr update
systemctl enable --now fwupd-refresh.timer

# capsule updates boot fwupdx64.efi; sbctl's pacman hook re-signs it on every fwupd upgrade once it is in sbctl's list
efi=/usr/lib/fwupd/efi/fwupdx64.efi
if sbctl_ready && [[ -f "$efi" ]]; then
    sbctl sign -s -o "$efi.signed" "$efi"
fi

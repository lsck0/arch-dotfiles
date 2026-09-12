#!/usr/bin/env bash

if ! command -v mount.cifs >/dev/null 2>&1; then
    exit 0
fi

set -ex

sudo mkdir -p /mnt/homelab
sudo cp ${PWD}/mnt-homelab.mount /etc/systemd/system/
sudo cp ${PWD}/mnt-homelab.automount /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable mnt-homelab.automount

# add NAS to nemo/nautilus sidebar bookmarks
mkdir -p "${HOME}/.config/gtk-3.0"
BOOKMARK="${HOME}/.config/gtk-3.0/bookmarks"
grep -qxF "smb://smb.lsck0.dev/homelab Homelab" "$BOOKMARK" 2>/dev/null \
  || echo "smb://smb.lsck0.dev/homelab Homelab" >> "$BOOKMARK"

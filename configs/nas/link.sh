#!/usr/bin/env bash
set -ex

sudo mkdir -p /mnt/homelab
sudo cp ${PWD}/mnt-homelab.mount /etc/systemd/system/
sudo cp ${PWD}/mnt-homelab.automount /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now mnt-homelab.automount

# Add NAS to Nemo/Nautilus sidebar bookmarks
mkdir -p "${HOME}/.config/gtk-3.0"
BOOKMARK="${HOME}/.config/gtk-3.0/bookmarks"
grep -qxF "smb://smb.lsck0.dev/homelab homelab" "$BOOKMARK" 2>/dev/null \
  || echo "smb://smb.lsck0.dev/homelab homelab" >> "$BOOKMARK"

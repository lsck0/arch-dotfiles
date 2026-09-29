#!/usr/bin/env bash
cd "$(dirname "$(readlink -f "$0")")" || exit 1

if ! command -v mount.cifs >/dev/null 2>&1; then
    exit 0
fi

set -ex

sudo mkdir -p /mnt/homelab
sudo cp ${PWD}/mnt-homelab.mount /etc/systemd/system/
sudo cp ${PWD}/mnt-homelab.automount /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable mnt-homelab.automount
ln -sfn /mnt/homelab "${HOME}/nas"
# sidebar bookmark lives in xdg/link.sh

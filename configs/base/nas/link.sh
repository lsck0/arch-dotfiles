#!/usr/bin/env bash
cd "$(dirname "$(readlink -f "$0")")" || exit 1

source ../../../scripts/lib/personal.sh
is_personal || exit 0

if ! command -v mount.cifs >/dev/null 2>&1; then
    exit 0
fi

set -e

sudo mkdir -p /mnt/homelab
sed -e "s|@UID@|$(id -u)|" -e "s|@GID@|$(id -g)|" "${PWD}/mnt-homelab.mount" | sudo tee /etc/systemd/system/mnt-homelab.mount >/dev/null
sudo cp "${PWD}/mnt-homelab.automount" /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable mnt-homelab.automount
ln -sfn /mnt/homelab "${HOME}/nas"
# sidebar bookmark lives in xdg/link.sh

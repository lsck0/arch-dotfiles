#!/usr/bin/env bash
cd "$(dirname "$(readlink -f "$0")")" || exit 1

source $DOTFILES/scripts/lib/personal.sh
source $DOTFILES/scripts/lib/secrets.sh
is_personal || exit 0

if ! command -v mount.cifs >/dev/null 2>&1; then
    exit 0
fi

set -e

CRED=/etc/samba/homelab.cred

# no credentials, no mount: never fall back to a guest mount
if ! secret_is_plaintext "$DOTFILES/secrets/samba-homelab"; then
    echo "nas: no plaintext secrets/samba-homelab, the homelab mount stays off" >&2
    sudo systemctl disable --now mnt-homelab.automount mnt-homelab.mount 2>/dev/null || true
    sudo rm -f /etc/systemd/system/mnt-homelab.mount /etc/systemd/system/mnt-homelab.automount "$CRED"
    sudo systemctl daemon-reload
    exit 0
fi

sudo install -Dm600 -o root -g root "$DOTFILES/secrets/samba-homelab" "$CRED"
sudo mkdir -p /mnt/homelab
sed -e "s|@UID@|$(id -u)|" -e "s|@GID@|$(id -g)|" "${PWD}/mnt-homelab.mount" | sudo tee /etc/systemd/system/mnt-homelab.mount >/dev/null
sudo cp "${PWD}/mnt-homelab.automount" /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable mnt-homelab.automount
ln -sfn /mnt/homelab "${HOME}/nas"
# sidebar bookmark lives in xdg/link.sh

#!/usr/bin/env bash
cd "$(dirname "$(readlink -f "$0")")" || exit 1

if [[ ! -d /var/lib/portmaster ]]; then
    echo "portmaster: /var/lib/portmaster missing, skipping" >&2
    exit 0
fi

set -e

# copy, ProtectHome=read-only blocks portmaster saving through a link into /home
if ! sudo cmp -s config.json /var/lib/portmaster/config.json; then
    sudo install -m 644 config.json /var/lib/portmaster/config.json
    # read at start only; stays stopped while toggle-protonvpn.sh or toggle-firewall.sh holds it off
    sudo systemctl try-restart portmaster.service
fi

if [[ -f /etc/xdg/autostart/portmaster-autostart.desktop ]]; then
    mkdir -p "${HOME}/.config/autostart"
    ln -sfn "${PWD}/portmaster-autostart.desktop" "${HOME}/.config/autostart/portmaster-autostart.desktop"
fi

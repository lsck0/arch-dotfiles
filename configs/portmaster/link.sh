#!/usr/bin/env bash
cd "$(dirname "$(readlink -f "$0")")" || exit 1

if [[ ! -d /var/lib/portmaster ]]; then
    echo "portmaster: /var/lib/portmaster missing, skipping" >&2
    exit 0
fi

set -ex

# copy, ProtectHome=read-only blocks portmaster saving through a link into /home
sudo install -m 644 "${PWD}/config.json" /var/lib/portmaster/config.json

if [[ -f /etc/xdg/autostart/portmaster-autostart.desktop ]]; then
    mkdir -p "${HOME}/.config/autostart"
    ln -sfn "${PWD}/portmaster-autostart.desktop" "${HOME}/.config/autostart/portmaster-autostart.desktop"
fi

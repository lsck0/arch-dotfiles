#!/usr/bin/env bash
cd "$(dirname "$(readlink -f "$0")")" || exit 1

set -e

# auto-vpn and the protonvpn toggle stop portmaster while the tunnel is up; polkit grants it without a password
if [[ -d /etc/polkit-1/rules.d ]]; then
    sudo install -m644 49-portmaster.rules /etc/polkit-1/rules.d/49-portmaster.rules
fi

chmod 755 ./auto-vpn.sh
install -Dm644 auto-vpn.service "${HOME}/.config/systemd/user/auto-vpn.service"
systemctl --user daemon-reload
systemctl --user enable --now auto-vpn.service

#!/usr/bin/env bash
cd "$(dirname "$(readlink -f "$0")")" || exit 1

set -e

source $DOTFILES/scripts/lib/personal.sh

# auto-vpn and the protonvpn toggle stop portmaster while the tunnel is up; polkit grants it without a password
sudo install -m644 49-portmaster.rules /etc/polkit-1/rules.d/49-portmaster.rules

install -Dm644 auto-vpn.service "${HOME}/.config/systemd/user/auto-vpn.service"
systemctl --user daemon-reload
# guests have no proton account
if is_personal; then
    systemctl --user enable --now auto-vpn.service
else
    systemctl --user disable --now auto-vpn.service 2>/dev/null || true
fi

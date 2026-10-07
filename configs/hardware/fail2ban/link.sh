#!/usr/bin/env bash
cd "$(dirname "$(readlink -f "$0")")" || exit 1

set -e

if cmp -s jail.local /etc/fail2ban/jail.local; then
    sudo systemctl enable --now fail2ban.service
else
    sudo install -Dm644 jail.local /etc/fail2ban/jail.local
    sudo systemctl enable fail2ban.service
    # 1.1.1's reload drops a changed banaction instead of swapping it, bans persist in its db
    sudo systemctl restart fail2ban.service
fi

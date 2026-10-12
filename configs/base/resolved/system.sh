#!/usr/bin/env bash
# DoT (Quad9) for off-VPN DNS via systemd-resolved, homelab/VPN split-DNS preserved; wsl uses the host resolver
[[ "$FORM_FACTOR" != wsl ]] || exit 0

install -Dm644 resolved.conf /etc/systemd/resolved.conf.d/dotfiles.conf
ln -sfn /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf
systemctl enable systemd-resolved.service
systemctl restart systemd-resolved.service 2>/dev/null || true

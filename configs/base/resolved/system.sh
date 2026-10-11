#!/usr/bin/env bash
# DoT (Quad9) for off-VPN DNS via systemd-resolved, with homelab/VPN split-DNS preserved. Replaces the openresolv
# path: NetworkManager now feeds per-link DNS straight to resolved (dns=systemd-resolved, see NetworkManager.conf),
# and wg-quick's DNS= goes through systemd-resolvconf (packages.txt) to resolved as wg0's per-link resolver.
# wsl uses the host resolver.
[[ "$FORM_FACTOR" != wsl ]] || exit 0
command -v resolvectl >/dev/null 2>&1 || { echo "resolved: systemd-resolved missing, skipping" >&2; exit 0; }

install -Dm644 resolved.conf /etc/systemd/resolved.conf.d/dotfiles.conf
ln -sfn /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf
systemctl enable systemd-resolved.service
systemctl restart systemd-resolved.service 2>/dev/null || true

#!/usr/bin/env bash
cd "$(dirname "$(readlink -f "$0")")" || exit 1
source ../../../scripts/lib/platform.sh
# nft also arrives under wsl, as a dependency of docker, where windows owns the firewall
if ! command -v nft >/dev/null 2>&1 || [[ "$(platform_form_factor ../../..)" == wsl ]]; then
    exit 0
fi
set -e
# .nft lives in /etc (real file), so no /home dependency at boot
sudo mkdir -p /etc/nftables.d
sudo install -m 644 fw-inbound.nft /etc/nftables.d/fw-inbound.nft
sudo install -m 644 fw-lockdown.nft /etc/nftables.d/fw-lockdown.nft
sudo install -m 644 fw-inbound.service /etc/systemd/system/fw-inbound.service
# never enabled: scripts/toggles/toggle-firewall.sh starts it, a reboot or this script returns to fw-inbound
sudo install -m 644 fw-lockdown.service /etc/systemd/system/fw-lockdown.service
sudo systemctl daemon-reload
sudo systemctl enable fw-inbound.service
# reload swaps the table atomically; `enable --now` would not reload a running unit
sudo systemctl reload-or-restart fw-inbound.service

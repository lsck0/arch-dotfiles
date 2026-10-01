#!/usr/bin/env bash
cd "$(dirname "$(readlink -f "$0")")" || exit 1
if ! command -v nft >/dev/null 2>&1; then
    exit 0
fi
set -e
# .nft lives in /etc (real file), so no /home dependency at boot
sudo mkdir -p /etc/nftables.d
sudo install -m 644 fw-inbound.nft /etc/nftables.d/fw-inbound.nft
sudo install -m 644 fw-lockdown.nft /etc/nftables.d/fw-lockdown.nft
sudo install -m 644 fw-inbound.service /etc/systemd/system/fw-inbound.service
sudo systemctl daemon-reload
sudo systemctl enable fw-inbound.service
# restart: `enable --now` would not reload a running unit
sudo systemctl restart fw-inbound.service

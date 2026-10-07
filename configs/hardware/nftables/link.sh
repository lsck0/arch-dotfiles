#!/usr/bin/env bash
cd "$(dirname "$(readlink -f "$0")")" || exit 1
source $DOTFILES/scripts/lib/platform.sh
# nft also arrives under wsl, as a dependency of docker, where windows owns the firewall
if ! command -v nft >/dev/null 2>&1 || [[ "$(platform_form_factor "$DOTFILES")" == wsl ]]; then
    exit 0
fi
set -e
# .nft lives in /etc (real file), so no /home dependency at boot
sudo mkdir -p /etc/nftables.d
sudo install -m 644 fw-inbound.nft /etc/nftables.d/fw-inbound.nft
sudo install -m 644 fw-lockdown.nft /etc/nftables.d/fw-lockdown.nft
sudo install -m 644 fw-inbound.service /etc/systemd/system/fw-inbound.service
# lockdown is the resting state: boot and every network down return to it, only a home up (persona dispatcher) or
# scripts/toggles/toggle-firewall.sh lifts it; the disable moves a machine set up when fw-inbound was the default
sudo install -m 644 fw-lockdown.service /etc/systemd/system/fw-lockdown.service
sudo systemctl daemon-reload
sudo systemctl disable fw-inbound.service
sudo systemctl enable fw-lockdown.service
# reload swaps the table of whichever is running atomically; never start one here, that would drop a chosen state
sudo systemctl try-reload-or-restart fw-inbound.service fw-lockdown.service

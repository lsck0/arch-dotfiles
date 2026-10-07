#!/usr/bin/env bash

# nft also arrives under wsl, as a dependency of docker, where windows owns the firewall
if ! command -v nft >/dev/null 2>&1 || [[ "$FORM_FACTOR" == wsl ]]; then
    exit 0
fi
# .nft lives in /etc (real file), so no /home dependency at boot
install -Dm644 fw-inbound.nft /etc/nftables.d/fw-inbound.nft
install -Dm644 fw-lockdown.nft /etc/nftables.d/fw-lockdown.nft
# lockdown is the resting state: boot and every network down return to it, only a home up (persona dispatcher) or
# scripts/toggles/toggle-firewall.sh lifts it; the disable moves a machine set up when fw-inbound was the default
unit_install fw-inbound.service fw-lockdown.service
systemctl disable fw-inbound.service
systemctl enable fw-lockdown.service
# reload swaps the table of whichever is running atomically; never start one here, that would drop a chosen state
systemctl try-reload-or-restart fw-inbound.service fw-lockdown.service

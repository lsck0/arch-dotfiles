#!/usr/bin/env bash

# nft also arrives under wsl, as a dependency of docker, where windows owns the firewall
if ! command -v nft >/dev/null 2>&1 || [[ "$FORM_FACTOR" == wsl ]]; then
    exit 0
fi
# .nft lives in /etc (real file), so no /home dependency at boot
install -Dm644 fw-inbound.nft /etc/nftables.d/fw-inbound.nft
install -Dm644 fw-lockdown.nft /etc/nftables.d/fw-lockdown.nft
# the egress rules let the tor daemon out of an untrusted link; numeric, a name nft cannot resolve would fail the load
file_render fw-egress.nft /etc/nftables.d/fw-egress.nft TOR_UID="$(id -u tor 2>/dev/null || echo 4294967295)"
# lockdown is the resting state: boot and every network down return to it, only a home up (persona dispatcher) or
# scripts/toggles/toggle-firewall.sh lifts it; the disable moves a machine set up when fw-inbound was the default
unit_install fw-inbound.service fw-lockdown.service fw-egress.service
systemctl disable fw-inbound.service
systemctl enable fw-lockdown.service
# a vm guest leaves through its host, whose fw_egress forward chain already holds it to the host's network rule
if [[ "$FORM_FACTOR" == vm ]]; then
    systemctl disable --now fw-egress.service
else
    systemctl enable fw-egress.service
fi
# reload swaps the table of whichever is running atomically; never start one here, that would drop a chosen state.
# fw-egress starts at boot and on the next network up (persona dispatcher), not mid-run: off home it would close
# this very run's network until the dispatcher brings tor up
systemctl try-reload-or-restart fw-inbound.service fw-lockdown.service fw-egress.service

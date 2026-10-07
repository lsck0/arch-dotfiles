#!/usr/bin/env bash
# NM dispatcher, after 90-anonymous-persona started avahi: a home link up queues the driverless printers found there.
# a unit, not inline: discovery takes seconds and dispatcher scripts run one after another
iface="${1:-}"
action="${2:-}"
[ "$action" = up ] || exit 0

HOME_NETWORK=/run/home-network

grep -qx "$iface" "$HOME_NETWORK" 2>/dev/null || exit 0
systemctl start --no-block printers-sync.service

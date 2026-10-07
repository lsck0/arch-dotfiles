#!/usr/bin/env bash
# drop 99-gamemode.conf (split_lock_mitigate=0 machine wide), the gamemode hook now relaxes it only while a game runs
set -euo pipefail

SYSCTL_CONF=/etc/sysctl.d/99-gamemode.conf
SPLIT_LOCK_MITIGATE=/proc/sys/kernel/split_lock_mitigate
MITIGATE_ON=1

[[ -e "$SYSCTL_CONF" ]] || exit 0
rm -f "$SYSCTL_CONF"
if [[ -e "$SPLIT_LOCK_MITIGATE" ]]; then
    sysctl -q kernel.split_lock_mitigate="$MITIGATE_ON"
fi

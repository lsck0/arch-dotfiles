#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")"
source ./lib.sh

# extracted from the quickshell Network widget, which was silently broken inline

TUNNELS=(toggle-vpn.sh toggle-protonvpn.sh toggle-tor.sh)

# offline means both halves are down
check() {
    [[ "$(nmcli networking 2>/dev/null)" == disabled ]] || { echo off; return; }
    # match "unblocked" exactly: it contains "blocked", so grep -v blocked never matches
    rfkill --output SOFT --noheadings 2>/dev/null | grep -qx unblocked && { echo off; return; }
    echo on
}

turn_on() {
    for t in "${TUNNELS[@]}"; do
        [[ "$(./"$t" get 2>/dev/null || echo off)" == on ]] || continue
        ./"$t" off || echo "offline: failed to tear down $t, continuing" >&2
    done
    nmcli networking off || true
    rfkill block all || true
}

turn_off() {
    rfkill unblock all || true
    nmcli networking on || true
}

toggle_main offline "Offline Mode" check turn_on turn_off "${1:-toggle}"

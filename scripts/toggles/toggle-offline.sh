#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")"
source ./lib.sh

TUNNELS=(toggle-vpn.sh toggle-protonvpn.sh toggle-tor.sh)
# the radios that were on before offline mode; tmpfs, since rfkill ids are renumbered on boot
RFKILL_SAVED="$TOGGLES_RUNTIME_DIR/offline-rfkill"

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
    # already offline: everything reads blocked now, keep the earlier snapshot
    [[ "$(check)" == on ]] || rfkill -rno ID,SOFT | awk '$2 == "unblocked" {print $1}' >"$RFKILL_SAVED" || true
    nmcli networking off || true
    rfkill block all || true
}

turn_off() {
    if [[ -f "$RFKILL_SAVED" ]]; then
        xargs -r rfkill unblock <"$RFKILL_SAVED" || true
        rm -f "$RFKILL_SAVED"
    else
        rfkill unblock all || true
    fi
    nmcli networking on || true
}

toggle_main offline "Offline Mode" check turn_on turn_off "${1:-toggle}"

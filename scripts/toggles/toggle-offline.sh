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
    local t up=()
    for t in "${TUNNELS[@]}"; do
        [[ "$(./"$t" get 2>/dev/null || echo off)" == on ]] || continue
        up+=("$t")
        ./"$t" off || echo "offline: failed to tear down $t, continuing" >&2
    done
    # already offline: everything reads blocked now, keep the earlier snapshots
    if [[ "$(check)" == off ]]; then
        rfkill -rno ID,SOFT | awk '$2 == "unblocked" {print $1}' >"$RFKILL_SAVED" || true
        # the tunnels come back with the network, or it stays down; tmpfs, a reboot starts over anyway
        toggle_set_volatile offline-tunnels "${up[*]}"
    fi
    # announced as on only when both halves really went down
    nmcli networking off
    rfkill block all
}

turn_off() {
    local failed=() tunnels
    tunnels=" $(toggle_get_volatile offline-tunnels) "
    if [[ -f "$RFKILL_SAVED" ]]; then
        xargs -r rfkill unblock <"$RFKILL_SAVED"
    else
        rfkill unblock all
    fi
    # tor routes without a link, so it is back before the network and nothing it covered leaves in the clear meanwhile
    if [[ "$tunnels" == *" toggle-tor.sh "* ]]; then ./toggle-tor.sh on >/dev/null || failed+=(toggle-tor.sh); fi
    nmcli networking on
    # wg0 may name its endpoint by hostname and protonvpn dials out: both need the network first
    if [[ "$tunnels" == *" toggle-vpn.sh "* ]]; then ./toggle-vpn.sh on >/dev/null || failed+=(toggle-vpn.sh); fi
    if [[ "$tunnels" == *" toggle-protonvpn.sh "* ]]; then
        { nm-online -qt 30 && ./toggle-protonvpn.sh on >/dev/null; } || failed+=(toggle-protonvpn.sh)
    fi
    rm -f "$RFKILL_SAVED" "$TOGGLES_RUNTIME_DIR/offline-tunnels"
    # the network stays up: a wifi that needs picking or a captive portal would otherwise keep every way back offline.
    # a tunnel that was up and is not is said loudly instead, never silently
    ((${#failed[@]} == 0)) \
        || toggle_notify -a Toggles -u critical "Offline Mode" "Back online, but ${failed[*]} did not come back: traffic is not tunnelled"
}

toggle_main offline "Offline Mode" check turn_on turn_off "${1:-toggle}"

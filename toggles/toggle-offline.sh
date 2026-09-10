#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")"
source ./lib.sh

# Extracted from the quickshell Network widget, which ran a bare
# `rfkill block all` inline — and which was silently broken.
#
# THE BUG THIS FIXES: rfkill governs *radios only*. `rfkill list` on this
# machine shows Bluetooth and Wireless LAN and nothing else, while the
# ethernet port `enp0s31f6` exists and is NetworkManager-managed. So
# `rfkill block all` left a wired connection fully up while the widget
# reported "offline mode on" — the worst possible failure for a feature
# whose entire job is to guarantee the opposite. `nmcli networking off`
# is what actually covers ethernet (and wifi, and any future NM device).
#
# Tunnels come down FIRST, and deliberately so: wg0 is raw `wg-quick`,
# outside NetworkManager's view, so `nmcli networking off` does not touch
# it. Killing the transport out from under a live tunnel also tends to
# leave the interface and its routes behind rather than tearing them down
# cleanly. Tor and ProtonVPN go first for the same reason (ProtonVPN's
# also restarts portmaster.service on the way down — see
# toggle-protonvpn.sh).
#
# Going back online does NOT restore the tunnels. Silently reconnecting a
# VPN is a bigger surprise than leaving it down, and the tunnel toggles are
# one click away in the same panel.
#
# Open decision (see research/ROADMAP.md): paired Bluetooth input devices
# are not exempted. None are paired today, so "disable everything" is the
# honest reading of "full offline mode"; revisit if a BT keyboard/mouse is
# ever added, or offline mode will disconnect the keyboard you use to
# turn it back off.

TUNNELS=(toggle-vpn.sh toggle-protonvpn.sh toggle-tor.sh)

# Offline means *both* halves are down. Reporting on when only the radios
# are blocked is exactly the lie this script exists to stop telling.
check() {
    [[ "$(nmcli networking 2>/dev/null)" == disabled ]] || { echo off; return; }
    # Match "unblocked" exactly, not `grep -v blocked` — "unblocked"
    # contains "blocked", so the negated form matches nothing and always
    # reports on.
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

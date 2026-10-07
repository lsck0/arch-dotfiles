#!/usr/bin/env bash
: "${DOTFILES:=$HOME/projects/arch-dotfiles}"
# connect protonvpn once per untrusted network, when it first has full connectivity (so a captive portal logs in first),
# disconnect once on arriving home. home is /run/home-network (networkmanager home-network.sh). watches NM for changes.
set -uo pipefail
TOGGLE="$DOTFILES/scripts/toggles/toggle-protonvpn.sh"
HOME_FLAG=/run/home-network

decide() {
    local net
    # the active connection path is new on every activation: another interface, network or reconnect is a change
    net=$(nmcli -t -f TYPE,STATE,CON-PATH device 2>/dev/null | awk -F: '($1=="ethernet"||$1=="wifi") && $2=="connected"{print $3; exit}')
    [ -n "$net" ] || return 0
    # transitions only: a vpn toggled by hand stays as it is until the network changes
    if [ -e "$HOME_FLAG" ]; then
        [ "$last" != home ] && [ "$("$TOGGLE" get 2>/dev/null)" = on ] && "$TOGGLE" off
        last=home
    elif [ "$last" != "$net" ] && [ "$(nmcli -t -f CONNECTIVITY general status 2>/dev/null)" = full ]; then
        last=$net
        [ "$("$TOGGLE" get 2>/dev/null)" = off ] && "$TOGGLE" on
    fi
}

last=
decide
nmcli monitor 2>/dev/null | while read -r _; do decide; done

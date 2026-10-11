#!/usr/bin/env bash
: "${DOTFILES:=$HOME/projects/arch-dotfiles}"
# connect protonvpn on an untrusted network, disconnect once on arriving home; watches NM for changes. home is every
# connected wifi/ethernet device listed in /run/home-network (configs/base/networkmanager/home-network.sh). only the
# vpn half: before login and until proton0 is up the system layer keeps the link closed and on tor (fw-egress, the
# persona dispatcher), so a connect is tried at once, through tor, with no connectivity check, and retried with backoff
set -uo pipefail
TOGGLE="$DOTFILES/scripts/toggles/toggle-protonvpn.sh"
HOME_FLAG=/run/home-network
RETRY_FIRST_S=15
RETRY_MAX_S=300
# then it waits for the next network change: tor keeps carrying, and each failure was already notified by the toggle
RETRY_ATTEMPTS=6

last=
attempts=0
# SECONDS of the next attempt, 0 while none is pending
retry_at=0

decide() {
    local net="" home=1 dev type state path delay
    # the active connection path is new on every activation: another interface, network or reconnect is a change
    # DEVICE last: a bluetooth one is an address, its escaped colons stay in the remainder
    while IFS=: read -r type state path dev; do
        case "$type" in ethernet | wifi | gsm | bt) ;; *) continue ;; esac
        [ "$state" = connected ] || continue
        net+="$path "
        # mobile data is never home
        case "$type" in gsm | bt) home=0 ;; *) grep -qx "$dev" "$HOME_FLAG" 2>/dev/null || home=0 ;; esac
    done < <(nmcli -t -f TYPE,STATE,CON-PATH,DEVICE device 2>/dev/null)
    [ -n "$net" ] || { retry_at=0; return 0; }
    # transitions only: a vpn toggled by hand stays as it is until the network changes
    if ((home)); then
        [ "$last" != home ] && [ "$("$TOGGLE" get 2>/dev/null)" = on ] && "$TOGGLE" off
        last=home
        retry_at=0
        return 0
    fi
    if [ "$last" != "$net" ]; then
        last=$net
        attempts=0
        retry_at=0
    fi
    ((attempts < RETRY_ATTEMPTS && SECONDS >= retry_at)) || return 0
    if [ "$("$TOGGLE" get 2>/dev/null)" = on ] || "$TOGGLE" on; then
        attempts=$RETRY_ATTEMPTS
        retry_at=0
        return 0
    fi
    attempts=$((attempts + 1))
    delay=$((RETRY_FIRST_S << (attempts - 1)))
    ((delay < RETRY_MAX_S)) || delay=$RETRY_MAX_S
    retry_at=0
    ((attempts < RETRY_ATTEMPTS)) && retry_at=$((SECONDS + delay))
    return 0
}

decide
# a line is an NM event, a timeout the pending retry; eof means nmcli ended, and the unit restarts this
nmcli monitor 2>/dev/null | while :; do
    if ((retry_at)); then
        read -r -t "$((retry_at > SECONDS ? retry_at - SECONDS : 1))" _
    else
        read -r _
    fi
    status=$?
    ((status == 0 || status > 128)) || exit 0
    decide
done

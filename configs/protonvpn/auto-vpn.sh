#!/usr/bin/env bash
# connect protonvpn on an untrusted network once it has full connectivity (so a captive portal logs in first),
# disconnect at home. home is the hardware mac in use (networkmanager's permanent policy). watches NM for changes.
set -uo pipefail
TOGGLE="${HOME}/projects/arch-dotfiles/toggles/toggle-protonvpn.sh"

decide() {
    local iface cur perm conn on
    iface=$(nmcli -t -f DEVICE,TYPE,STATE device 2>/dev/null | awk -F: '($2=="ethernet"||$2=="wifi") && $3=="connected"{print $1; exit}')
    [ -n "$iface" ] || return 0
    cur=$(cat "/sys/class/net/${iface}/address" 2>/dev/null)
    perm=$(ethtool -P "$iface" 2>/dev/null | awk '{print $NF}')
    conn=$(nmcli -t -f CONNECTIVITY general status 2>/dev/null)
    on=$("$TOGGLE" get 2>/dev/null)
    if [ -n "$perm" ] && [ "$cur" = "$perm" ]; then
        [ "$on" = on ] && "$TOGGLE" off
    elif [ "$conn" = full ]; then
        [ "$on" = off ] && "$TOGGLE" on
    fi
}

decide
nmcli monitor 2>/dev/null | while read -r _; do decide; done

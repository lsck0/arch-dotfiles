#!/usr/bin/env bash
# NM dispatcher, first of the three: the one home rule. a physical link is home while it is on its hardware mac and its
# default gateway's mac is in home-gateways; /run/home-network lists those links one per line and is gone without one
iface="${1:-}"
action="${2:-}"
case "$action" in up | down) ;; *) exit 0 ;; esac

GATEWAYS=/etc/NetworkManager/home-gateways
HOME_NETWORK=/run/home-network

# physical wifi/ethernet only; a home link that vanished (usb unplug) still counts on its down
[ -e "/sys/class/net/${iface}/device" ] || grep -qx "$iface" "$HOME_NETWORK" 2>/dev/null || exit 0

home=""
# no gateways file (guest, locked secrets) leaves every link foreign
[ -s "$GATEWAYS" ] && for n in /sys/class/net/*; do
    i=${n##*/}
    [ -e "$n/device" ] || continue
    [ "$action" = down ] && [ "$i" = "$iface" ] && continue
    # NM puts a random mac on every foreign network; only home profiles keep the hardware one
    perm=$(ethtool -P "$i" 2>/dev/null | awk '{print $NF}')
    [ -n "$perm" ] && [ "$(cat "$n/address")" = "$perm" ] || continue
    gw=$(ip -4 route show default dev "$i" | awk '{print $3; exit}')
    [ -n "$gw" ] || continue
    # right after a connect the gateway is often unresolved; one ping fills the neighbour table
    ip neigh show "$gw" dev "$i" | grep -q lladdr || ping -c1 -W1 -I "$i" "$gw" >/dev/null 2>&1
    mac=$(ip neigh show "$gw" dev "$i" | awk '$2 == "lladdr" {print $3}')
    [ -n "$mac" ] && grep -qixF "$mac" "$GATEWAYS" && home+="$i"$'\n'
done

if [ -n "$home" ]; then
    # readers poll it, so swap it in whole
    printf '%s' "$home" >"$HOME_NETWORK.new"
    chmod 644 "$HOME_NETWORK.new"
    mv -f "$HOME_NETWORK.new" "$HOME_NETWORK"
else
    rm -f "$HOME_NETWORK"
fi

#!/usr/bin/env bash
# netns.sh up|down: the "protonvpn" network namespace, whose only way out is a wireguard tunnel to proton. the tunnel's
# udp socket stays in the main namespace with wg-quick's fwmark 51820, so fw-egress lets it out on any link (the same
# rule as for proton0); inside, nothing but lo and the tunnel exist, so a dead tunnel means no network, never a leak
set -euo pipefail

NS=protonvpn
IFACE=wg-protonvpn
CONF=/etc/wireguard/protonvpn-netns.conf
FWMARK=51820

down() {
    ip netns del "$NS" 2>/dev/null || true
    ip link del "$IFACE" 2>/dev/null || true
}

up() {
    local addr
    down
    ip netns add "$NS"
    ip -n "$NS" link set lo up
    ip link add "$IFACE" type wireguard
    wg setconf "$IFACE" <(wg-quick strip "$CONF")
    wg set "$IFACE" fwmark "$FWMARK"
    ip link set "$IFACE" netns "$NS"
    local v6=0
    for addr in $(sed -n 's/^[[:space:]]*Address[[:space:]]*=//p' "$CONF" | tr ',' ' '); do
        ip -n "$NS" addr add "$addr" dev "$IFACE"
        [[ "$addr" == *:* ]] && v6=1
    done
    ip -n "$NS" link set "$IFACE" mtu 1420 up
    ip -n "$NS" route add default dev "$IFACE"
    # with no ipv6 address in the tunnel it is off, so nothing waits on a v6 route that cannot exist
    if ((v6)); then
        ip -n "$NS" -6 route add default dev "$IFACE"
    else
        ip netns exec "$NS" sysctl -qw net.ipv6.conf.all.disable_ipv6=1
    fi
}

case "${1:-}" in
up) up ;;
down) down ;;
*) echo "usage: $0 up|down" >&2; exit 2 ;;
esac

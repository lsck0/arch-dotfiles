#!/usr/bin/nu --no-config-file
# the "protonvpn" network namespace, whose only way out is a wireguard tunnel to proton. the tunnel's udp socket stays
# in the main namespace with wg-quick's fwmark 51820, so fw-egress lets it out on any link (the same rule as for
# proton0); inside, nothing but lo and the tunnel exist, so a dead tunnel means no network, never a leak

const NS = "protonvpn"
const IFACE = "wg-protonvpn"
const CONF = "/etc/wireguard/protonvpn-netns.conf"
const FWMARK = "51820"
const MTU = "1420"

def "main down" []: nothing -> nothing {
    do { ^ip netns del $NS } | complete | ignore
    do { ^ip link del $IFACE } | complete | ignore
}

def "main up" []: nothing -> nothing {
    main down
    ^ip netns add $NS
    ^ip -n $NS link set lo up
    ^ip link add $IFACE type wireguard
    ^wg-quick strip $CONF | ^wg setconf $IFACE /dev/stdin
    ^wg set $IFACE fwmark $FWMARK
    ^ip link set $IFACE netns $NS
    let addresses = open --raw $CONF | lines | parse --regex '^\s*Address\s*=(?<v>.*)$' | get v | split row ","
        | str trim | where $it != ""
    for address in $addresses { ^ip -n $NS addr add $address dev $IFACE }
    ^ip -n $NS link set $IFACE mtu $MTU up
    ^ip -n $NS route add default dev $IFACE
    # with no ipv6 address in the tunnel it is off, so nothing waits on a v6 route that cannot exist
    if ($addresses | any { $in | str contains ":" }) {
        ^ip -n $NS -6 route add default dev $IFACE
    } else {
        ^ip netns exec $NS sysctl -qw net.ipv6.conf.all.disable_ipv6=1
    }
}

def main []: nothing -> nothing {
    print --stderr "usage: netns up|down"
    exit 2
}

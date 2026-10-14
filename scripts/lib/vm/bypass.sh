# shellcheck shell=bash
# bypass.sh <nft file> <phase>, in an empty namespace on the guest
set -uo pipefail
nft_file=$1 phase=$2
ip link set lo up
for dev in home0 tun0 wan0; do
    ip link add "$dev" type dummy
    ip link set "$dev" up
done
ip addr add 192.168.178.10/24 dev home0
ip addr add 10.8.0.2/24 dev tun0
ip addr add fd00::2/64 dev tun0 nodad
ip addr add 203.0.113.2/24 dev wan0
ip addr add 2001:db8:ff::2/64 dev wan0 nodad
for net in 10.0.0.0/8 172.16.0.0/12 192.168.50.0/24 1.1.1.1/32 fc00::/7 2001:db8::/32; do ip route add "$net" dev tun0; done
ip route add 172.20.0.0/16 dev wan0
ip route add default dev wan0
ip -6 route add default dev wan0
nft -f "$nft_file" || {
    echo "drill: bypass_load_$phase=failed"
    exit 1
}
nft -f - << 'EOF'
table inet drill_probe {
    set seen4 { type ipv4_addr . inet_service; flags dynamic; }
    set seen6 { type ipv6_addr . inet_service; flags dynamic; }
    set marked4 { type ipv4_addr . inet_service; flags dynamic; }
    set marked6 { type ipv6_addr . inet_service; flags dynamic; }
    chain output {
        type filter hook output priority mangle + 10; policy accept;
        ct state != new return
        meta l4proto { tcp, udp } meta nfproto ipv4 add @seen4 { ip daddr . th dport }
        meta l4proto { tcp, udp } meta nfproto ipv6 add @seen6 { ip6 daddr . th dport }
        meta l4proto { tcp, udp } meta nfproto ipv4 ct mark 1710 add @marked4 { ip daddr . th dport }
        meta l4proto { tcp, udp } meta nfproto ipv6 ct mark 1710 add @marked6 { ip6 daddr . th dport }
    }
}
EOF
# stands in for what the start-post fills in from getent and /run/home-network
nft add element inet portmaster_bypass gids '{ @MEMBER_GID@ }'
[[ "$phase" != home ]] || nft add element inet portmaster_bypass home_ifaces '{ "home0" }'

# probe <phase> <name> <tcp|udp> <daddr> <dport> <gid>: reports marked, unmarked or unseen
probe() {
    local fam=4 got=unseen
    [[ "$1" == "$phase" ]] || return 0
    [[ "$4" != *:* ]] || fam=6
    setpriv --regid="$6" --clear-groups timeout 1 bash -c "echo > /dev/$3/$4/$5" 2> /dev/null
    if nft get element inet drill_probe "seen$fam" "{ $4 . $5 }" > /dev/null 2>&1; then
        got=unmarked
        ! nft get element inet drill_probe "marked$fam" "{ $4 . $5 }" > /dev/null 2>&1 || got=marked
    fi
    echo "drill: bypass_$2=$got"
}

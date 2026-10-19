# bypass.nu <nft file> <phase>, in an empty namespace on the guest; vm.nu fills in the probes and the member gid

const PROBES = '@PROBES@'
const PROBE_TABLE = r#'
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
'#

def probe-has [set: string, element: string]: nothing -> bool {
    (^nft get element inet drill_probe $set $element | complete).exit_code == 0
}

def main [nft_file: path, phase: string] {
    ^ip link set lo up
    for dev in [home0 tun0 wan0] {
        ^ip link add $dev type dummy
        ^ip link set $dev up
    }
    ^ip addr add 192.168.178.10/24 dev home0
    ^ip addr add 10.8.0.2/24 dev tun0
    ^ip addr add fd00::2/64 dev tun0 nodad
    ^ip addr add 203.0.113.2/24 dev wan0
    ^ip addr add 2001:db8:ff::2/64 dev wan0 nodad
    for net in [10.0.0.0/8 172.16.0.0/12 192.168.50.0/24 1.1.1.1/32 fc00::/7 2001:db8::/32] { ^ip route add $net dev tun0 }
    ^ip route add 172.20.0.0/16 dev wan0
    ^ip route add default dev wan0
    ^ip -6 route add default dev wan0
    try { ^nft -f $nft_file } catch {
        print $"drill: bypass_load_($phase)=failed"
        exit 1
    }
    $PROBE_TABLE | ^nft -f -
    ^nft add element inet portmaster_bypass gids '{ @MEMBER_GID@ }'
    if $phase == home { ^nft add element inet portmaster_bypass home_ifaces '{ "home0" }' }
    for probe in ($PROBES | from nuon | where phase == $phase) {
        let family = if ($probe.daddr | str contains ":") { 6 } else { 4 }
        let element = $"{ ($probe.daddr) . ($probe.dport) }"
        # bash: its /dev/tcp and /dev/udp redirects open the socket
        ^setpriv $"--regid=($probe.gid)" --clear-groups timeout 1 bash -c $"echo > /dev/($probe.proto)/($probe.daddr)/($probe.dport)" | complete | ignore
        let got = if not (probe-has $"seen($family)" $element) { "unseen" } else if (probe-has $"marked($family)" $element) { "marked" } else { "unmarked" }
        print $"drill: bypass_($probe.name)=($got)"
    }
}

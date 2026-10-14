#!/usr/bin/nu --no-config-file
# transparent tor routing for IPv4 and IPv6 (based on edu4rdshl/tor-router), in its own table inet tor_router so
# portmaster's, docker's and fail2ban's rules stay untouched and stop is a single table delete

const TABLE = "tor_router"
const TRANS_PORT = 9040
const DNS_PORT = 6669
# the fwmark a tunnel puts on its own udp: protonvpn's and wg-quick's, as in configs/base/nftables/fw-egress.nft
const TUNNEL_MARKS = "0x0ea13b2c, 0x0000ca6c"
const HOME_NETWORK = "/run/home-network"
# HOMELAB_DNS (the lab router, reached plain for the split-horizon zone: configs/base/networkmanager) and
# HOMELAB_NETS, on a homelab machine only
const HOMELAB_ENV = "/etc/NetworkManager/homelab.env"
const RULESET = r#'add table inet @TABLE@
delete table inet @TABLE@
table inet @TABLE@ {
	# lan and homelab stay direct, but only out a home link, the homelab also through wg0; anywhere else they go via tor
	set home_ifaces { type ifname; }
	# home_ifaces fills lan4: the homelab nets and each home link's subnet
	set lan4 { type ipv4_addr; flags interval; auto-merge; }
	set homelab4 { type ipv4_addr; flags interval; @HOMELAB4@ }
	set lab_dns { type ipv4_addr; @LAB_DNS@ }
	# 127.192.0.0/10 is torrc's VirtualAddrNetworkIPv4 and must reach the TransPort
	set direct4 { type ipv4_addr; flags interval; elements = { 127.0.0.0/9, 127.128.0.0/10 } }
	# link-local and loopback only
	set direct6 { type ipv6_addr; flags interval; elements = { fe80::/10, ::1/128 } }

	# before portmaster's dns redirect at dstnat, so lookups reach tor's DNSPort
	chain nat_output {
		type nat hook output priority dstnat - 10; policy accept;
		meta skuid @TOR_UID@ return
		# a vpn's handshake goes out as itself, so the persona dispatcher's tor can hand over to protonvpn
		meta l4proto udp meta mark { @TUNNEL_MARKS@ } return
		# the dhcp client's unicast renew and broadcast rebind; redirected, the lease runs out
		udp sport 68 udp dport 67 return
		# the homelab's split-horizon dns stays plain to the lab router out a home link, before the redirect below
		# sends 53 to tor
		oifname @home_ifaces ip daddr @lab_dns meta l4proto { tcp, udp } th dport 53 return
		udp dport 53 redirect to :@DNS_PORT@
		tcp dport 53 redirect to :@TRANS_PORT@
		# no lo: the automapped 127.192.0.0/10 must still reach the TransPort
		oifname { "virbr*", "docker*", "br-*", "veth*", "waydroid*", "lxc*" } return
		oifname @home_ifaces ip daddr @lan4 return
		oifname "wg0" ip daddr @homelab4 return
		ip daddr @direct4 return
		ip6 daddr @direct6 return
		meta l4proto { tcp, udp } redirect to :@TRANS_PORT@
	}

	chain filter_output {
		type filter hook output priority filter; policy accept;
		ct direction reply accept
		oifname { "lo", "virbr*", "docker*", "br-*", "veth*", "waydroid*", "lxc*" } accept
		oifname @home_ifaces ip daddr @lan4 accept
		oifname "wg0" ip daddr @homelab4 accept
		ip daddr 127.0.0.0/8 accept
		ip6 daddr @direct6 accept
		meta skuid @TOR_UID@ accept
		meta l4proto udp meta mark { @TUNNEL_MARKS@ } accept
		udp sport 68 udp dport 67 accept
		icmpv6 type { nd-neighbor-solicit, nd-neighbor-advert } accept
		# connections opened before start fail fast instead of continuing in the clear
		meta l4proto tcp reject with tcp reset
		# catch-all so icmp and other protocols cannot leak
		reject
	}

	# vms and containers cannot reach the TransPort, so everything they forward is blocked, lan and homelab included;
	# no wg* so guests cannot leave through a tunnel
	chain filter_forward {
		type filter hook forward priority filter - 1; policy accept;
		ct direction reply accept
		oifname { "docker*", "br-*", "veth*", "virbr*", "waydroid*", "lxc*" } accept
		reject
	}
}
'#

def homelab []: nothing -> record {
    let vars = if ($HOMELAB_ENV | path exists) {
        open --raw $HOMELAB_ENV | lines | parse --regex '^(?<key>[A-Z_]+)=(?<value>.*)$'
        | reduce --fold {} {|v, acc| $acc | upsert $v.key ($v.value | str trim --char '"') }
    } else { {} }
    {dns: ($vars.HOMELAB_DNS? | default ""), nets: ($vars.HOMELAB_NETS? | default "" | split row " " | where $it != "")}
}

def elements [values: list<string>]: nothing -> string {
    if ($values | is-empty) { "" } else { $"elements = { ($values | str join ',') }" }
}

# home_ifaces <- /run/home-network, lan4 <- the homelab nets plus each home link's own subnet: the lan and homelab
# bypass tor only out a home link, so a foreign network on the same subnet goes through tor; the persona dispatcher
# calls it on every link change. flushed first, a failed fill only keeps the lan on tor
def home-fill []: nothing -> nothing {
    let ifaces = try { open --raw $HOME_NETWORK | lines | where $it != "" } catch { [] }
    let links = $ifaces | each {|i|
        ^ip -4 route show dev $i scope link proto kernel | lines | each { split row " " | first }
    }
    let nets = (homelab).nets ++ ($links | flatten) | uniq | sort
    ^nft flush set inet $TABLE home_ifaces
    ^nft flush set inet $TABLE lan4
    if ($ifaces | is-not-empty) { ^nft add element inet $TABLE home_ifaces $"{ ($ifaces | str join ',') }" }
    if ($nets | is-not-empty) { ^nft add element inet $TABLE lan4 $"{ ($nets | str join ',') }" }
}

def "main start" []: nothing -> nothing {
    if (^systemctl is-active tor.service | complete).exit_code != 0 {
        print "The tor service is not active, please start the tor service before running the script."
        exit 1
    }
    let lab = homelab
    let values = {
        TABLE: $TABLE TRANS_PORT: $TRANS_PORT DNS_PORT: $DNS_PORT TUNNEL_MARKS: $TUNNEL_MARKS
        TOR_UID: (^id -u tor | str trim) HOMELAB4: (elements $lab.nets)
        LAB_DNS: (elements (if $lab.dns == "" { [] } else { [$lab.dns] }))
    }
    $values | items {|k, v| {k: $k, v: $v} }
    | reduce --fold $RULESET {|p, text| $text | str replace --all $"@($p.k)@" ($p.v | into string) }
    | ^nft -f -
    try { home-fill } catch { print --stderr "tor-router: home links not filled in, the lan goes through tor" }
}

def "main home" []: nothing -> nothing {
    if (^nft list table inet $TABLE | complete).exit_code != 0 { return }
    home-fill
}

def "main stop" []: nothing -> nothing {
    ^nft destroy table inet $TABLE
}

def "main restart" []: nothing -> nothing {
    main stop
    main start
}

# Transparent tor routing: start, stop, restart, or home (refill the lan bypass for the current home links).
def main []: nothing -> nothing {
    print "Usage: tor-router {start|stop|restart|home}"
}

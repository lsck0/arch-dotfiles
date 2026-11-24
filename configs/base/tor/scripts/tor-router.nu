#!/usr/bin/env -S nu --no-config-file -I /var/lib/dotfiles/repo/scripts/lib
# its own table, so portmaster's, docker's and fail2ban's rules stay untouched and stop is one table delete

use state.nu [env-file-load file-lines text-render]

const TABLE = "tor_router"
const TRANS_PORT = 9040
const DNS_PORT = 6669
const TUNNEL_MARKS = "0x0ea13b2c, 0x0000ca6c"
const HOME_NETWORK = "/run/home-network"
const TRUSTED_NETWORK = "/run/trusted-network"
const HOMELAB_ENV = "/etc/NetworkManager/homelab.env"
const WG_IFACE = "wg0"
# base/ssh's router and desktop addresses, rendered in by the module: a full tunnel routes the house lan through
# table 51820, so the main table names none of them
const WG_HOSTS = "@WG_HOSTS@"
const RULESET = r#'add table inet @TABLE@
delete table inet @TABLE@
table inet @TABLE@ {
	# the lan stays direct only out a trusted link, the homelab only out a home one (and wg0), so a foreign same-subnet
	# lan goes via tor
	set trusted_links { type ifname; }
	set lan4 { type ipv4_addr; flags interval; auto-merge; }
	# the homelab's subnets and dns, the house's hosts, and what the main table routes out wg0: its tunnel subnet and a
	# split tunnel's lans; never a full tunnel's default
	set wg4 { type ipv4_addr; flags interval; auto-merge; }
	set lab_dns { type ipv4_addr; @LAB_DNS@ }
	# 127.192.0.0/10 is torrc's VirtualAddrNetworkIPv4 and must reach the TransPort
	set direct4 { type ipv4_addr; flags interval; elements = { 127.0.0.0/9, 127.128.0.0/10 } }
	set direct6 { type ipv6_addr; flags interval; elements = { fe80::/10, ::1/128 } }

	# before portmaster's dns redirect at dstnat, so lookups reach tor's DNSPort
	chain nat_output {
		type nat hook output priority dstnat - 10; policy accept;
		meta skuid @TOR_UID@ return
		# a vpn's handshake goes out as itself, so the persona dispatcher's tor can hand over to protonvpn
		meta l4proto udp meta mark { @TUNNEL_MARKS@ } return
		# the dhcp client's unicast renew and broadcast rebind; redirected, the lease runs out
		udp sport 68 udp dport 67 return
		# the homelab's split-horizon dns stays plain out a home link or wg0, before the redirect below
		oifname @trusted_links ip daddr @lab_dns meta l4proto { tcp, udp } th dport 53 return
		oifname "wg0" ip daddr @wg4 return
		udp dport 53 redirect to :@DNS_PORT@
		tcp dport 53 redirect to :@TRANS_PORT@
		# no lo: the automapped 127.192.0.0/10 must still reach the TransPort
		oifname { "virbr*", "docker*", "br-*", "veth*", "waydroid*", "lxc*" } return
		oifname @trusted_links ip daddr @lan4 return
		ip daddr @direct4 return
		ip6 daddr @direct6 return
		meta l4proto { tcp, udp } redirect to :@TRANS_PORT@
	}

	chain filter_output {
		type filter hook output priority filter; policy accept;
		ct direction reply accept
		oifname { "lo", "virbr*", "docker*", "br-*", "veth*", "waydroid*", "lxc*" } accept
		oifname @trusted_links ip daddr @lan4 accept
		oifname "wg0" ip daddr @wg4 accept
		ip daddr 127.0.0.0/8 accept
		ip6 daddr @direct6 accept
		meta skuid @TOR_UID@ accept
		meta l4proto udp meta mark { @TUNNEL_MARKS@ } accept
		udp sport 68 udp dport 67 accept
		icmpv6 type { nd-neighbor-solicit, nd-neighbor-advert } accept
		# connections opened before start fail fast instead of continuing in the clear
		meta l4proto tcp reject with tcp reset
		# icmp and other protocols cannot leak
		reject
	}

	# guests cannot reach the TransPort, so their forwarding is blocked; no wg*, so they cannot leave through a tunnel
	chain filter_forward {
		type filter hook forward priority filter - 1; policy accept;
		ct direction reply accept
		oifname { "docker*", "br-*", "veth*", "virbr*", "waydroid*", "lxc*" } accept
		reject
	}
}
'#

def homelab []: nothing -> record {
    let vars = env-file-load $HOMELAB_ENV
    {dns: ($vars.HOMELAB_DNS? | default ""), nets: ($vars.HOMELAB_NETS? | default "" | split row " " | where $it != "")}
}

# The prefixes the main table routes out link, never a full tunnel's default or its two /1 halves; a missing link has
# none.
def routes [link: string, ...filter: string]: nothing -> list<string> {
    ^ip -4 route show dev $link ...$filter | complete | get stdout | lines | each { split row " " | first }
    | where $it != default and not ($it =~ '/[01]$')
}

# Refills the lan bypass for the current trusted links (the homelab's subnets only with a home one among them) and
# wg0's; flushed first, so a failed fill only keeps the lan on tor.
def home-fill []: nothing -> nothing {
    let ifaces = file-lines $TRUSTED_NETWORK
    let lab = homelab
    let home_lab = if (file-lines $HOME_NETWORK | is-empty) { [] } else { $lab.nets }
    let sets = {
        trusted_links: $ifaces
        lan4: ($home_lab ++ ($ifaces | each { routes $in scope link proto kernel } | flatten))
        wg4: ($lab.nets ++ [$lab.dns] ++ ($WG_HOSTS | split row " ") ++ (routes $WG_IFACE))
    }
    $sets | items {|set, elements|
        ^nft flush set inet $TABLE $set
        let unique = $elements | where $it != "" | uniq | sort
        if ($unique | is-not-empty) { ^nft add element inet $TABLE $set $"{ ($unique | str join ',') }" }
    } | ignore
}

def "main start" []: nothing -> nothing {
    if (^systemctl is-active tor.service | complete).exit_code != 0 {
        print --stderr "tor-router: tor.service is not active, start it first"
        exit 1
    }
    let dns = (homelab).dns
    $RULESET | text-render {
        TABLE: $TABLE TRANS_PORT: $TRANS_PORT DNS_PORT: $DNS_PORT TUNNEL_MARKS: $TUNNEL_MARKS
        TOR_UID: (^id -u tor | str trim) LAB_DNS: (if $dns == "" { "" } else { $"elements = { ($dns) }" })
    }
    | ^nft -f -
    try { home-fill } catch { print --stderr "tor-router: trusted links not filled in, the lan goes through tor" }
}

# Also on wg0 up and down (the persona dispatcher): its routes change.
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

# Transparent tor routing: start, stop, restart, or home (refill the lan bypass for the current trusted links).
def main []: nothing -> nothing {
    print "usage: tor-router {start|stop|restart|home}"
}

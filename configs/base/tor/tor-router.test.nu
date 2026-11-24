#!/usr/bin/env -S nu --no-config-file
# tor-router's ruleset under fw-egress's kill switch, in an unprivileged network namespace with a dummy uplink: a
# lookup and a connection out the uplink must land on tor's DNSPort and TransPort, and nothing may leave by the uplink.

const HERE = path self .
const ROUTER = $HERE | path join scripts tor-router.nu
const EGRESS = $HERE | path join .. nftables config fw-egress.nft
const UPLINK = "d0"
const UPLINK_ADDRESS = "10.9.9.2/24"
const UPLINK_GATEWAY = "10.9.9.1"
const REMOTE = "9.9.9.9"
const SEND_TIMEOUT = "2"

use std/assert
use ../../../scripts/lib/state.nu [text-render]

def router-consts []: nothing -> record {
    open --raw $ROUTER | parse --regex '(?m)^const (?<k>[A-Z_]+) = "?(?<v>[^"\n]*)"?$' | transpose --header-row --as-record
}

# tor-router.nu's RULESET with its own constants filled in; tor is a uid other than the test's, no homelab
def ruleset []: nothing -> string {
    open --raw $ROUTER | parse --regex "(?s)const RULESET = r#'(?<r>.*?)'#" | get 0.r
    | text-render (router-consts | merge {TOR_UID: ((^id -u | into int) + 1) LAB_DNS: ""})
}

# Sends one tcp connect (to each port) and one udp datagram to the remote, then reads where they ended up: the
# packets that reached the input of lo per port, and every packet that left by the uplink.
const PROBE = 'set -e
ip link set lo up
ip link add @UPLINK@ type dummy
ip addr add @ADDRESS@ dev @UPLINK@
ip link set @UPLINK@ up
ip route add default via @GATEWAY@
nft -f @EGRESS@
nft -f @RULES@
nft -f - <<EOF
table inet probe {
	chain input { type filter hook input priority -300; iifname "lo" meta l4proto { tcp, udp } th dport { @TRANS@, @DNS@ } counter; }
	chain post { type filter hook postrouting priority 300; oifname "@UPLINK@" counter; }
}
EOF
set +e
for p in 443 853 53; do timeout @T@ bash -c "echo > /dev/tcp/@REMOTE@/$p" 2>/dev/null; done
timeout @T@ bash -c "echo q > /dev/udp/@REMOTE@/53" 2>/dev/null
nft -j list table inet probe'

def probe [rules: path]: nothing -> record {
    let consts = router-consts
    let script = $PROBE | text-render {
        UPLINK: $UPLINK ADDRESS: $UPLINK_ADDRESS GATEWAY: $UPLINK_GATEWAY EGRESS: $EGRESS RULES: $rules
        TRANS: $consts.TRANS_PORT DNS: $consts.DNS_PORT REMOTE: $REMOTE T: $SEND_TIMEOUT
    }
    let r = ^unshare -rn bash -c $script | complete
    assert ($r.exit_code == 0) $"probe failed: ($r.stderr)"
    let rules = $r.stdout | from json | get nftables | where { $in.rule? != null } | get rule
    let count = {|chain| $rules | where chain == $chain | get 0.expr | where { $in.counter? != null } | get 0.counter.packets }
    {loopback: (do $count input), uplink: (do $count post)}
}

def main [] {
    let tools = [nft unshare bash timeout ip]
    if (which ...$tools | length) < ($tools | length) or (^unshare -rn ip link add t0 type dummy | complete).exit_code != 0 {
        print --stderr "tor-router.test: skipped: needs nft, iproute2 and unprivileged network namespaces"
        return
    }
    let dir = mktemp --directory --tmpdir dot-tor-router-test-XXXXXX
    let rules = $dir | path join tor-router.nft
    let text = ruleset
    # the wg0 resolver (the router's tunnel address, the lab dns) keeps its split-horizon answers away from home
    let line = {|rule| $text | lines | enumerate | where ($it.item | str trim) == $rule | get 0.index }
    assert ((do $line 'oifname "wg0" ip daddr @wg4 return') < (do $line $"udp dport 53 redirect to :((router-consts).DNS_PORT)")) "wg0 dns goes into tor"
    $text | save $rules
    let r = probe $rules
    # tor not up: no router table, so the kill switch alone stands and still lets nothing out
    let bare = $dir | path join none.nft
    "" | save $bare
    let alone = probe $bare
    rm --recursive --force $dir
    assert equal $alone.uplink 0 "packets left by the uplink with fw-egress alone"
    # three tcp syns (443, dot on 853, dns over tcp) and one udp lookup, each redirected into tor
    assert ($r.loopback >= 4) $"($r.loopback) of 4 redirected packets reached tor's ports past fw-egress"
    assert equal $r.uplink 0 "packets left by the uplink around tor"
}

#!/usr/bin/env -S nu --no-config-file
# tor-router's ruleset under fw-egress's kill switch, in an unprivileged network namespace with a dummy uplink: a
# lookup and a connection out the uplink must land on tor's DNSPort and TransPort, and nothing may leave by the uplink.

const HERE = path self | path dirname
const ROUTER = $HERE | path join tor-router.nu
const EGRESS = $HERE | path join .. nftables fw-egress.nft
const UPLINK = "d0"
const UPLINK_ADDRESS = "10.9.9.2/24"
const UPLINK_GATEWAY = "10.9.9.1"
const REMOTE = "9.9.9.9"
const SEND_TIMEOUT = "2"

def fail [msg: string] { error make {msg: $"tor-router.test: ($msg)"} }

# tor-router.nu's RULESET with its own constants filled in; tor is a uid other than the test's, no homelab
def ruleset []: nothing -> string {
    let code = open --raw $ROUTER
    let text = $code | parse --regex "(?s)const RULESET = r#'(?<r>.*?)'#" | get 0.r
    let consts = $code | parse --regex '(?m)^const (?<k>[A-Z_]+) = "?(?<v>[^"\n]*)"?$'
    let values = $consts | append [
        {k: TOR_UID, v: ((^id -u | into int) + 1 | into string)} {k: HOMELAB4, v: ""} {k: LAB_DNS, v: ""}
    ]
    $values | reduce --fold $text {|p, acc| $acc | str replace --all $"@($p.k)@" $p.v }
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
    let script = [
        [UPLINK $UPLINK] [ADDRESS $UPLINK_ADDRESS] [GATEWAY $UPLINK_GATEWAY] [EGRESS $EGRESS] [RULES $rules]
        [TRANS (open --raw $ROUTER | parse --regex 'const TRANS_PORT = (?<p>\d+)' | get 0.p)]
        [DNS (open --raw $ROUTER | parse --regex 'const DNS_PORT = (?<p>\d+)' | get 0.p)]
        [REMOTE $REMOTE] [T $SEND_TIMEOUT]
    ] | reduce --fold $PROBE {|p, acc| $acc | str replace --all $"@($p.0)@" $p.1 }
    let r = ^unshare -rn bash -c $script | complete
    if $r.exit_code != 0 { fail $"probe failed: ($r.stderr)" }
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
    ruleset | save $rules
    let r = probe $rules
    # tor not up: no router table, so the kill switch alone stands and still lets nothing out
    let bare = $dir | path join none.nft
    "" | save $bare
    let alone = probe $bare
    rm --recursive --force $dir
    if $alone.uplink != 0 { fail $"($alone.uplink) packets left by the uplink with fw-egress alone" }
    # three tcp syns (443, dot on 853, dns over tcp) and one udp lookup, each redirected into tor
    if $r.loopback < 4 { fail $"($r.loopback) of 4 redirected packets reached tor's ports past fw-egress" }
    if $r.uplink != 0 { fail $"($r.uplink) packets left by the uplink around tor" }
}

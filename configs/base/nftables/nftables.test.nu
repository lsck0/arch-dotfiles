#!/usr/bin/env -S nu --no-config-file
# fw-egress.service's own load, run in an unprivileged network namespace: the kill switch loads with pacman's escape
# filled in, also on a fresh install where the tor user does not exist yet. fw-inbound from a peer namespace over a
# veth: sshd's port drops until the three ports were knocked in order, then accepts, and a source past ssh_rate is
# dropped again. The system verb keeps the lockdown ruleset the resting state, whose input policy is drop.

use module.nu [decls-flatten]
use mod.nu [system]

const HERE = path self .
const UNIT = $HERE | path join fw-egress.service
const RULESET = $HERE | path join fw-egress.nft
const ESCAPES = {fetch_uid: alpm, resolver_uid: systemd-resolve}
const INBOUND = $HERE | path join fw-inbound.nft
const INBOUND_VALUES = {
    SSH_KNOCK_WINDOW: "1h", SSH_PORT: "2222", SSH_RATE: "10/minute burst 10 packets"
    KNOCK_1: "7001", KNOCK_2: "7002", KNOCK_3: "7003"
}
# a rate low enough to cross in a few connections
const PROBE_RATE = "4/minute burst 4 packets"
const HOST_ADDRESS = "10.77.0.1"
const PEER_ADDRESS = "10.77.0.2"
# a dropped SYN is waited out, a refused one (accepted, nothing listening) answers at once
const CONNECT_TIMEOUT = "0.2"
const EXIT_TIMEOUT = 124
const LOCKDOWN = $HERE | path join fw-lockdown.nft
const LOCKDOWN_UNIT = $HERE | path join fw-lockdown.service
const PENTEST_IFACE = "tun0"
const PENTEST_LINKS = 'elements = { "tun0" }'

def fail [msg: string] { error make {msg: $"nftables.test: ($msg)"} }

# ExecStart's shell command with systemd's escapes undone and the installed paths pointed at the repo; ExecReload
# must be the same load, as only ExecStart's runs here.
def load-command [trusted_network: path]: nothing -> string {
    let lines = open --raw $UNIT | lines
    let start = $lines | where ($it | str starts-with "ExecStart=") | get 0 | str replace "ExecStart=" ""
    let reload = $lines | where ($it | str starts-with "ExecReload=") | get 0 | str replace "ExecReload=" ""
    if $reload != $start { fail "ExecReload is not ExecStart's load" }
    $start | str replace "/bin/sh -c '" "" | str substring 0..-2
    | str replace --all '$$' '$' | str replace --all '%%' '%'
    | str replace --all /etc/nftables.d/fw-egress.nft $RULESET | str replace --all /usr/sbin/nft nft
    | str replace --all /run/trusted-network $trusted_network
}

def set-elements [ruleset: list, name: string]: nothing -> list {
    $ruleset | where { $in.set?.name? == $name } | get 0.set.elem? | default []
}

def load [command: string, path_dirs: list<path>]: nothing -> list {
    let r = with-env {PATH: ($path_dirs ++ $env.PATH)} { ^unshare -rn sh -c $"($command)\nnft -j list table inet fw_egress" | complete }
    if $r.exit_code != 0 { fail $"load failed: ($r.stderr)" }
    $r.stdout | from json | get nftables
}

# fw-inbound.nft as the module renders it, loaded: tun0 is in its set only with pentest_listeners.
def inbound-rules [pentest_links: string]: nothing -> string {
    let text = $INBOUND_VALUES | merge {PENTEST_LINKS: $pentest_links} | transpose k v
        | reduce --fold (open --raw $INBOUND) {|p, acc| $acc | str replace --all $"@($p.k)@" $p.v }
    let file = mktemp --tmpdir dot-nftables-test-XXXXXX.nft
    $text | save --force $file
    let r = ^unshare -rn sh -c $"nft -f ($file) && nft list table inet fw" | complete
    rm --force $file
    if $r.exit_code != 0 { fail $"fw-inbound does not load \(pentest '($pentest_links)'\): ($r.stderr)" }
    $r.stdout
}

# Connects from a peer namespace to each port in turn, in a fresh namespace holding fw-inbound rendered with values:
# per attempt whether it got through (refused at once) or was dropped (timed out), then the ruleset's sets.
const PEER_PROBE = 'set -e
ip link set lo up
unshare -n sleep 30 &
peer=$!
trap "kill $peer" EXIT
sleep 0.1
ip link add va type veth peer name vb netns $peer
ip addr add @HOST@/24 dev va
ip link set va up
nsenter -t $peer -n sh -c "ip link set lo up; ip addr add @PEER@/24 dev vb; ip link set vb up"
nft -f @RULES@
set +e
for port in @PORTS@; do
	nsenter -t $peer -n timeout @T@ bash -c "echo > /dev/tcp/@HOST@/$port" 2>/dev/null
	echo "$port $?" >&2
done
nft -j list table inet fw'

def peer-probe [values: record, ports: list<int>]: nothing -> record {
    let rules = mktemp --tmpdir dot-nftables-test-XXXXXX.nft
    $values | transpose k v | reduce --fold (open --raw $INBOUND) {|p, acc| $acc | str replace --all $"@($p.k)@" ($p.v | into string) }
    | save --force $rules
    let script = [[HOST $HOST_ADDRESS] [PEER $PEER_ADDRESS] [RULES $rules] [PORTS ($ports | str join " ")] [T $CONNECT_TIMEOUT]]
    | reduce --fold $PEER_PROBE {|p, acc| $acc | str replace --all $"@($p.0)@" $p.1 }
    let r = ^unshare -rn bash -c $script | complete
    rm --force $rules
    if $r.exit_code != 0 { fail $"peer probe failed: ($r.stderr)" }
    let through = $r.stderr | lines | parse "{port} {rc}" | each { ($in.rc | into int) != $EXIT_TIMEOUT }
    {through: $through, ruleset: ($r.stdout | from json | get nftables)}
}

# Knocks, then sshd's port: through only after the three knocks in order, and past ssh_rate dropped per source.
def inbound-knock []: nothing -> nothing {
    let v = $INBOUND_VALUES | merge {PENTEST_LINKS: "", SSH_RATE: $PROBE_RATE}
    let ssh = $v.SSH_PORT | into int
    let k = [$v.KNOCK_1 $v.KNOCK_2 $v.KNOCK_3] | each { into int }
    let cases = [
        [what knocks through];
        ["no knock" [] false]
        ["the knock" $k true]
        ["the knock reversed" ($k | reverse) false]
        ["two of three" ($k | first 2) false]
        ["the last two" ($k | skip 1) false]
    ]
    for c in $cases {
        let got = peer-probe $v ($c.knocks ++ [$ssh]) | get through | last
        if $got != $c.through { fail $"fw-inbound: ($c.what): sshd's port (if $got { 'reached' } else { 'dropped' })" }
    }
    let flood = peer-probe $v ($k ++ (1..8 | each { $ssh }))
    let attempts = $flood.through | skip 3
    if not ($attempts | first) or ($attempts | last) { fail $"fw-inbound: knocked source past ssh_rate: ($attempts | to nuon)" }
    if $PEER_ADDRESS not-in (set-elements $flood.ruleset ssh_flood | each { if ($in | describe) =~ record { $in.elem.val } else { $in } }) {
        fail "fw-inbound: the knocked source is not in ssh_flood"
    }
}

# The resting state the system verb declares: lockdown enabled, the inbound ruleset only a trusted link's start, and
# lockdown's own input chain dropping by policy.
def lockdown-default []: nothing -> nothing {
    let cfg = {
        ssh_knock_window: "1h", ssh_rate: "30/minute burst 30 packets", pentest_listeners: false
        deps: {"base/ssh": {port: 2222, knock: [7001 7002 7003]}, "base/networkmanager": {untrusted_policy: lockdown-tor}}
    }
    # the engine runs a verb in its module dir, where its sources are
    let units = with-env {FORM_FACTOR: desktop} { cd $HERE; system $cfg } | decls-flatten | where kind == unit
    let state = {|u| $units | where target == $u | get --optional 0.state }
    if (do $state fw-lockdown.service) != enabled { fail "fw-lockdown.service is not enabled" }
    if (do $state fw-inbound.service) != disabled { fail "fw-inbound.service is not disabled" }
    let unit = open --raw $LOCKDOWN_UNIT
    if not ($unit =~ '(?m)^WantedBy=multi-user\.target$' and $unit =~ '(?m)^Conflicts=fw-inbound\.service$') {
        fail "fw-lockdown.service is not wanted at boot or does not displace fw-inbound"
    }
    let r = ^unshare -rn sh -c $"nft -f ($LOCKDOWN) && nft -j list chain inet fw input" | complete
    if $r.exit_code != 0 { fail $"fw-lockdown does not load: ($r.stderr)" }
    let policy = $r.stdout | from json | get nftables | where { $in.chain? != null } | get 0.chain.policy
    if $policy != drop { fail $"fw-lockdown's input policy is ($policy)" }
}

def main [] {
    if (which nft unshare | length) < 2 or (^unshare -rn true | complete).exit_code != 0 {
        print --stderr "nftables.test: skipped: needs nft and unprivileged user namespaces"
        return
    }
    let dir = mktemp --directory --tmpdir dot-nftables-test-XXXXXX
    let trusted_network = $dir | path join trusted-network
    "eth9\n" | save $trusted_network
    let command = load-command $trusted_network
    let rules = load $command []
    for e in ($ESCAPES | transpose set user) {
        let uid = ^id -u $e.user | str trim | into int
        if (set-elements $rules $e.set) != [$uid] { fail $"($e.set) is not ($e.user)'s uid ($uid)" }
    }
    if (set-elements $rules trusted_links) != [eth9] {
        fail "trusted_links did not take /run/trusted-network"
    }

    # a fresh install: no tor user, the switch still loads and pacman still gets out
    let shim = $dir | path join bin
    mkdir $shim
    "#!/bin/sh\n[ \"$2\" = tor ] && exit 1\nexec /usr/bin/id \"$@\"\n" | save ($shim | path join id)
    chmod +x ($shim | path join id)
    let fresh = load $command [$shim]
    rm --recursive --force $dir
    if (set-elements $fresh tor_uid | is-not-empty) { fail "tor_uid filled without a tor user" }
    if (set-elements $fresh fetch_uid | is-empty) { fail "no fetch_uid without a tor user" }

    if (inbound-rules "" | str contains $PENTEST_IFACE) { fail "fw-inbound opens tun0 without pentest_listeners" }
    if not (inbound-rules $PENTEST_LINKS | str contains $PENTEST_IFACE) { fail "fw-inbound leaves tun0 out with pentest_listeners" }
    lockdown-default
    inbound-knock
}

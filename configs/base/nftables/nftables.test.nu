#!/usr/bin/env -S nu --no-config-file
# fw-egress.service's own load, run in an unprivileged network namespace: the kill switch loads with pacman's escape
# filled in, also on a fresh install where the tor user does not exist yet. fw-inbound from a peer namespace over a
# veth: sshd's port drops until the three ports were knocked in order, then accepts, and a source past ssh_rate is
# dropped again; with base/ssh.server off the knock opens nothing. The system verb keeps the lockdown ruleset the
# resting state, whose input policy is drop. fw-devtools: its unit fills the owners' uids (every login's without an
# owner record) and the ports devtools-guard declares; a uid outside the set gets a reset, the owner's connect passes.

use std/assert
use module.nu [decls-flatten text-render]
use mod.nu [system devtools-guard]

const HERE = path self .
const UNIT = $HERE | path join services fw-egress.service
const RULESET = $HERE | path join config fw-egress.nft
const ESCAPES = {fetch_uid: alpm, resolver_uid: systemd-resolve}
const INBOUND = $HERE | path join config fw-inbound.nft
const INBOUND_VALUES = {
    SSH_KNOCK_WINDOW: "1h", SSH_PORT: "2222", SSH_RATE: "10/minute burst 10 packets"
    KNOCK_1: "7001", KNOCK_2: "7002", KNOCK_3: "7003", SSH_RULE_PREFIX: ""
}
const DEVTOOLS_UNIT = $HERE | path join services fw-devtools.service
const DEVTOOLS_RULESET = $HERE | path join config fw-devtools.nft
const DEVTOOLS_PORT = 9234
# a uid no login has, standing in for a service user
const FOREIGN_UID = 4242
# the login uid range the unit falls back to without an owner record
const LOGIN_UID_MIN = 1000
# a rate low enough to cross in a few connections
const PROBE_RATE = "4/minute burst 4 packets"
const HOST_ADDRESS = "10.77.0.1"
const PEER_ADDRESS = "10.77.0.2"
# a dropped SYN is waited out, a refused one (accepted, nothing listening) answers at once
const CONNECT_TIMEOUT = "0.2"
const EXIT_TIMEOUT = 124
const LOCKDOWN = $HERE | path join config fw-lockdown.nft
const LOCKDOWN_UNIT = $HERE | path join services fw-lockdown.service
const PENTEST_IFACE = "tun0"
const PENTEST_LINKS = 'elements = { "tun0" }'
const INBOUND_TARGET = "/etc/nftables.d/fw-inbound.nft"
# fw-inbound's ssh_flood drop, ssh_allowed accept and three knock rules
const SSH_RULES = 5

# ExecStart's shell command with systemd's escapes undone and the installed paths pointed at the repo; ExecReload
# must be the same load, as only ExecStart's runs here.
def load-command [trusted_network: path]: nothing -> string {
    let lines = open --raw $UNIT | lines
    let start = $lines | where ($it | str starts-with "ExecStart=") | get 0 | str replace "ExecStart=" ""
    let reload = $lines | where ($it | str starts-with "ExecReload=") | get 0 | str replace "ExecReload=" ""
    assert equal $reload $start "ExecReload is not ExecStart's load"
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
    assert ($r.exit_code == 0) $"load failed: ($r.stderr)"
    $r.stdout | from json | get nftables
}

# fw-inbound.nft as the module renders it, loaded: tun0 is in its set only with pentest_listeners.
def inbound-rules [pentest_links: string]: nothing -> string {
    let file = mktemp --tmpdir dot-nftables-test-XXXXXX.nft
    open --raw $INBOUND | text-render ($INBOUND_VALUES | merge {PENTEST_LINKS: $pentest_links}) | save --force $file
    let r = ^unshare -rn sh -c $"nft -f ($file) && nft list table inet fw" | complete
    rm --force $file
    assert ($r.exit_code == 0) $"fw-inbound does not load \(pentest '($pentest_links)'\): ($r.stderr)"
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
    open --raw $INBOUND | text-render $values | save --force $rules
    let script = $PEER_PROBE | text-render {
        HOST: $HOST_ADDRESS PEER: $PEER_ADDRESS RULES: $rules PORTS: ($ports | str join " ") T: $CONNECT_TIMEOUT
    }
    let r = ^unshare -rn bash -c $script | complete
    rm --force $rules
    assert ($r.exit_code == 0) $"peer probe failed: ($r.stderr)"
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
        assert equal $got $c.through $"fw-inbound: ($c.what): sshd's port (if $got { 'reached' } else { 'dropped' })"
    }
    let off = peer-probe ($v | merge {SSH_RULE_PREFIX: "# "}) ($k ++ [$ssh]) | get through | last
    assert not $off "fw-inbound: the knock reached sshd's port with base/ssh.server off"
    let flood = peer-probe $v ($k ++ (1..8 | each { $ssh }))
    let attempts = $flood.through | skip 3
    assert (($attempts | first) and not ($attempts | last)) $"fw-inbound: knocked source past ssh_rate: ($attempts | to nuon)"
    let flooded = set-elements $flood.ruleset ssh_flood | each { if ($in | describe) =~ record { $in.elem.val } else { $in } }
    assert ($PEER_ADDRESS in $flooded) "fw-inbound: the knocked source is not in ssh_flood"
}

# The resting state the system verb declares: lockdown enabled, the inbound ruleset only a trusted link's start, and
# lockdown's own input chain dropping by policy.
def lockdown-default []: nothing -> nothing {
    let cfg = {
        ssh_knock_window: "1h", ssh_rate: "30/minute burst 30 packets", pentest_listeners: false
        deps: {"base/ssh": {server: true, port: 2222, knock: [7001 7002 7003]}, "base/networkmanager": {untrusted_policy: lockdown-tor}}
    }
    # the engine runs a verb in its module dir, where its sources are
    let units = with-env {FORM_FACTOR: desktop} { cd $HERE; system $cfg } | decls-flatten | where kind == unit
    # sshd's flood, accept and three knock rules, as the system verb renders them with base/ssh.server
    let ssh_rules = {|server|
        with-env {FORM_FACTOR: desktop} { cd $HERE; system ($cfg | upsert deps."base/ssh".server $server) }
        | decls-flatten | where target == $INBOUND_TARGET | get 0.content | lines
        | where { $in =~ 'dport (2222|7001|7002|7003) ' } | each { str trim }
    }
    let on = do $ssh_rules true
    assert (($on | length) == $SSH_RULES and not ($on | any { str starts-with "#" })) $"sshd's rules with the server on: ($on | to nuon)"
    let off = do $ssh_rules false
    assert (($off | length) == $SSH_RULES and ($off | all { str starts-with "# " })) $"sshd's rules with the server off: ($off | to nuon)"
    let state = {|u| $units | where target == $u | get --optional 0.state }
    assert equal (do $state fw-lockdown.service) enabled "fw-lockdown.service is not enabled"
    assert equal (do $state fw-inbound.service) disabled "fw-inbound.service is not disabled"
    let unit = open --raw $LOCKDOWN_UNIT
    assert ($unit =~ '(?m)^WantedBy=multi-user\.target$' and $unit =~ '(?m)^Conflicts=fw-inbound\.service$') (
        "fw-lockdown.service is not wanted at boot or does not displace fw-inbound"
    )
    let r = ^unshare -rn sh -c $"nft -f ($LOCKDOWN) && nft -j list chain inet fw input" | complete
    assert ($r.exit_code == 0) $"fw-lockdown does not load: ($r.stderr)"
    let policy = $r.stdout | from json | get nftables | where { $in.chain? != null } | get 0.chain.policy
    assert equal $policy drop "fw-lockdown's input policy is not drop"
}

# fw-devtools.service's load against an owners file and a dir of port files, its ruleset copied with the include
# pointed there; ExecReload must be the same load.
def devtools-load [dir: path, owners: path]: nothing -> list {
    let lines = open --raw $DEVTOOLS_UNIT | lines
    let start = $lines | where ($it | str starts-with "ExecStart=") | get 0 | str replace "ExecStart=" ""
    let reload = $lines | where ($it | str starts-with "ExecReload=") | get 0 | str replace "ExecReload=" ""
    assert equal $reload $start "fw-devtools: ExecReload is not ExecStart's load"
    let ruleset = $dir | path join fw-devtools.nft
    open --raw $DEVTOOLS_RULESET | str replace /etc/nftables.d/devtools.d ($dir | path join ports) | save --force $ruleset
    let command = $start | str replace "/bin/sh -c '" "" | str substring 0..-2 | str replace --all '$$' '$'
        | str replace --all /etc/nftables.d/fw-devtools.nft $ruleset | str replace --all /usr/sbin/nft nft
        | str replace --all /var/lib/dotfiles/owners $owners
    let r = ^unshare -rn sh -c $"($command)\nnft -j list table inet fw_devtools" | complete
    assert ($r.exit_code == 0) $"fw-devtools does not load: ($r.stderr)"
    $r.stdout | from json | get nftables
}

# Connects to a listener on DEVTOOLS_PORT in a namespace holding fw-devtools with owner_uid {uid}: whether it got in.
const DEVTOOLS_PROBE = 'ip link set lo up
nft -f @RULES@ && nft add element inet fw_devtools owner_uid { @UID@ } || exit 2
python3 -I -c "import socket, time
s = socket.socket(); s.bind((\"127.0.0.1\", @PORT@)); s.listen(); time.sleep(3)" &
sleep 0.3
timeout 1 bash -c "echo > /dev/tcp/127.0.0.1/@PORT@" 2>/dev/null
rc=$?
kill $!
exit $rc'

def devtools-reaches [ruleset: path, uid: int]: nothing -> bool {
    let script = $DEVTOOLS_PROBE | text-render {RULES: $ruleset, UID: $uid, PORT: $DEVTOOLS_PORT}
    let r = ^unshare -rn bash -c $script | complete
    assert ($r.exit_code in [0 1]) $"fw-devtools probe failed: ($r.stderr)"
    $r.exit_code == 0
}

def devtools []: nothing -> nothing {
    let dir = mktemp --directory --tmpdir dot-nftables-test-XXXXXX
    let ports = $dir | path join ports
    mkdir $ports
    let guard = with-env {FORM_FACTOR: desktop} { devtools-guard fluxer $DEVTOOLS_PORT } | decls-flatten | get 0
    assert equal $guard.target /etc/nftables.d/devtools.d/fluxer.nft "devtools-guard writes outside fw-devtools' include"
    $guard.content | save ($ports | path join fluxer.nft)
    assert equal (with-env {FORM_FACTOR: wsl} { devtools-guard fluxer $DEVTOOLS_PORT }) null "devtools-guard declares on wsl"
    let me = ^id -u | str trim | into int
    let owners = $dir | path join owners
    $"(^id -un | str trim)\nno-such-login-dot-test\n" | save $owners
    let rules = devtools-load $dir $owners
    assert equal (set-elements $rules ports) [$DEVTOOLS_PORT] "fw-devtools ports did not take devtools-guard's file"
    assert equal (set-elements $rules owner_uid) [$me] "fw-devtools owner_uid is not the owners' uids"
    "" | save --force $owners
    let fallback = set-elements (devtools-load $dir $owners) owner_uid
    assert ($me in $fallback and ($fallback | all { $in >= $LOGIN_UID_MIN })) $"fw-devtools without an owner: ($fallback | to nuon)"
    rm --force $owners
    assert ($me in (set-elements (devtools-load $dir $owners) owner_uid)) "fw-devtools without an owners file"
    if (which python3 | is-not-empty) {
        let ruleset = $dir | path join fw-devtools.nft
        # inside the namespace this process is uid 0
        assert (devtools-reaches $ruleset 0) "fw-devtools resets the owner"
        assert not (devtools-reaches $ruleset $FOREIGN_UID) "fw-devtools lets another uid onto the port"
    }
    rm --recursive --force $dir
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
        assert equal (set-elements $rules $e.set) [$uid] $"($e.set) is not ($e.user)'s uid ($uid)"
    }
    assert equal (set-elements $rules trusted_links) [eth9] "trusted_links did not take /run/trusted-network"

    # a fresh install: no tor user, the switch still loads and pacman still gets out
    let shim = $dir | path join bin
    mkdir $shim
    "#!/bin/sh\n[ \"$2\" = tor ] && exit 1\nexec /usr/bin/id \"$@\"\n" | save ($shim | path join id)
    chmod +x ($shim | path join id)
    let fresh = load $command [$shim]
    rm --recursive --force $dir
    assert (set-elements $fresh tor_uid | is-empty) "tor_uid filled without a tor user"
    assert (set-elements $fresh fetch_uid | is-not-empty) "no fetch_uid without a tor user"

    assert not (inbound-rules "" | str contains $PENTEST_IFACE) "fw-inbound opens tun0 without pentest_listeners"
    assert (inbound-rules $PENTEST_LINKS | str contains $PENTEST_IFACE) "fw-inbound leaves tun0 out with pentest_listeners"
    lockdown-default
    inbound-knock
    devtools
}

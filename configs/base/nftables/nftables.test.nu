#!/usr/bin/env -S nu --no-config-file
# fw-egress.service's own load, run in an unprivileged network namespace: the kill switch loads with pacman's escape
# filled in, also on a fresh install where the tor user does not exist yet.

const HERE = path self .
const UNIT = $HERE | path join fw-egress.service
const RULESET = $HERE | path join fw-egress.nft
const ESCAPES = {fetch_uid: alpm, resolver_uid: systemd-resolve}
const INBOUND = $HERE | path join fw-inbound.nft
const MODULE = $HERE | path join mod.nu
const INBOUND_VALUES = {
    SSH_KNOCK_WINDOW: "1h", SSH_PORT: "2222", SSH_RATE: "10/minute burst 10 packets"
    KNOCK_1: "7001", KNOCK_2: "7002", KNOCK_3: "7003"
}
const PENTEST_KEYS = [PENTEST_INPUT PENTEST_FORWARD]
const PENTEST_IFACE = "tun0"

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

# fw-inbound.nft as the module renders it, loaded: the tun0 rules are there only with pentest_listeners.
def inbound-rules [pentest: bool]: nothing -> string {
    let consts = open --raw $MODULE | parse --regex "(?m)^const (?<k>[A-Z_]+) = '(?<v>[^'\n]*)'$"
    let pentest_values = $PENTEST_KEYS | each {|k|
        let rule = $consts | where k == $k | get --optional 0.v
        if $rule == null { fail $"mod.nu has no ($k)" }
        {k: $k, v: (if $pentest { $rule } else { "" })}
    }
    let text = $INBOUND_VALUES | transpose k v | append $pentest_values
        | reduce --fold (open --raw $INBOUND) {|p, acc| $acc | str replace --all $"@($p.k)@" $p.v }
    let file = mktemp --tmpdir dot-nftables-test-XXXXXX.nft
    $text | save --force $file
    let r = ^unshare -rn sh -c $"nft -f ($file) && nft list table inet fw" | complete
    rm --force $file
    if $r.exit_code != 0 { fail $"fw-inbound does not load \(pentest ($pentest)\): ($r.stderr)" }
    $r.stdout
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

    if (inbound-rules false | str contains $PENTEST_IFACE) { fail "fw-inbound opens tun0 without pentest_listeners" }
    let open_rules = inbound-rules true | lines | where ($it | str contains $PENTEST_IFACE) | length
    if $open_rules != ($PENTEST_KEYS | length) { fail "fw-inbound lacks a tun0 rule with pentest_listeners" }
}

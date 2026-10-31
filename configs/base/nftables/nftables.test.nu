#!/usr/bin/env -S nu --no-config-file
# fw-egress.service's own load, run in an unprivileged network namespace: the kill switch loads with pacman's escape
# filled in, also on a fresh install where the tor user does not exist yet.

const HERE = path self | path dirname
const UNIT = $HERE | path join fw-egress.service
const RULESET = $HERE | path join fw-egress.nft
const ESCAPES = {fetch_uid: alpm, resolver_uid: systemd-resolve}

def fail [msg: string] { error make {msg: $"nftables.test: ($msg)"} }

# ExecStart's shell command with systemd's escapes undone and the installed paths pointed at the repo.
def load-command [home: path]: nothing -> string {
    let line = open --raw $UNIT | lines | where ($it | str starts-with "ExecStart=/bin/sh -c '") | get 0
    $line | str replace "ExecStart=/bin/sh -c '" "" | str substring 0..-2
    | str replace --all '$$' '$' | str replace --all '%%' '%'
    | str replace --all /etc/nftables.d/fw-egress.nft $RULESET | str replace --all /usr/sbin/nft nft
    | str replace --all /run/home-network $home
}

def uid-set [ruleset: list, name: string]: nothing -> list<int> {
    $ruleset | where { $in.set?.name? == $name } | get 0.set.elem? | default []
}

def load [command: string, path_dirs: list<path>]: nothing -> list {
    let r = with-env {PATH: ($path_dirs ++ $env.PATH)} { ^unshare -rn sh -c $"($command)\nnft -j list table inet fw_egress" | complete }
    if $r.exit_code != 0 { fail $"load failed: ($r.stderr)" }
    $r.stdout | from json | get nftables
}

def main [] {
    if (which nft unshare | length) < 2 or (^unshare -rn true | complete).exit_code != 0 {
        print --stderr "nftables.test: skipped: needs nft and unprivileged user namespaces"
        return
    }
    let dir = mktemp --directory --tmpdir dot-nftables-test-XXXXXX
    let home = $dir | path join home-network
    "eth9\n" | save $home
    let command = load-command $home
    let rules = load $command []
    for e in ($ESCAPES | transpose set user) {
        let uid = ^id -u $e.user | str trim | into int
        if (uid-set $rules $e.set) != [$uid] { fail $"($e.set) is not ($e.user)'s uid ($uid)" }
    }
    if ($rules | where { $in.set?.name? == home_ifaces } | get 0.set.elem? | default []) != [eth9] {
        fail "home_ifaces did not take /run/home-network"
    }

    # a fresh install: no tor user, the switch still loads and pacman still gets out
    let shim = $dir | path join bin
    mkdir $shim
    "#!/bin/sh\n[ \"$2\" = tor ] && exit 1\nexec /usr/bin/id \"$@\"\n" | save ($shim | path join id)
    chmod +x ($shim | path join id)
    let fresh = load $command [$shim]
    rm --recursive --force $dir
    if (uid-set $fresh tor_uid | is-not-empty) { fail "tor_uid filled without a tor user" }
    if (uid-set $fresh fetch_uid | is-empty) { fail "no fetch_uid without a tor user" }
}

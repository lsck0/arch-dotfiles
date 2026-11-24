#!/usr/bin/env -S nu --no-config-file
# The persona a link event leaves: persona-dispatcher.nu run on a copy whose /run, /etc and /sys paths point into a
# scratch dir, with systemctl, sysctl, nmcli, resolvectl, ip, nft and systemd-run stubbed to log their argv. Per
# untrusted_policy and whether the link is trusted, the units started and stopped; a missing or unknown policy file is
# lockdown-tor, fail closed.

use std/assert

const HERE = path self .
const LIB = path self ../../../scripts/lib
const IFACE = "eth9"
const STUBS = [systemctl sysctl nmcli resolvectl ip nft systemd-run]
# the dispatcher's own paths, each moved under the scratch dir; one gone from the source fails the test
const MOVED = [
    /run/home-network /run/trusted-network /run/persona-lockdown /run/persona-tor /usr/local/bin/tor-router
    /usr/bin/tor /etc/NetworkManager/vm-guest /etc/NetworkManager/untrusted-policy
    /etc/systemd/system/dotfiles-stage.service /etc/NetworkManager/portal-seconds
]
const LOCKDOWN = [fw-egress.service fw-lockdown.service tor-router.service]

# The dispatcher and its lib copied into dir with every MOVED path and /sys/class/net under dir.
def stage [dir: path]: nothing -> path {
    let root = $dir | path join root
    let sources = [persona-dispatcher.nu lib/dispatch.nu] | each {|f| {file: $f, text: (open --raw ($HERE | path join scripts $f))} }
    let staged = $MOVED | reduce --fold $sources {|p, acc|
        let quoted = $"\"($p)\""
        assert ($acc | any { $in.text | str contains $quoted }) $"($p) is no longer a path of the dispatcher"
        $acc | update text { str replace --all $quoted $"\"($root)($p)\"" }
    }
    let copy = $dir | path join dispatcher
    mkdir ($copy | path join lib)
    for f in $staged {
        $f.text | str replace --all "/sys/class/net/" $"($root)/sys/class/net/" | save ($copy | path join $f.file)
    }
    mkdir ($root | path join sys class net $IFACE device) ($root | path join run) ($root | path join etc NetworkManager)
    mkdir ($root | path join usr bin) ($root | path join usr local bin)
    touch ($root | path join usr bin tor) ($root | path join usr local bin tor-router)
    # systemctl is-active and ip link show find nothing up; nmcli has the one link connected
    let bin = $dir | path join bin
    mkdir $bin
    for s in $STUBS {
        let body = match $s {
            systemctl => 'case "$1" in is-active|list-units) exit 3;; esac'
            ip => 'exit 1'
            nmcli => '[ "$1" = -t ] && echo "ethernet:connected:@IFACE@"; exit 0'
            _ => 'exit 0'
        }
        let script = $"#!/bin/sh\necho \"($s) $*\" >> \"($dir)/calls\"\n($body | str replace '@IFACE@' $IFACE)\n"
        $script | save ($bin | path join $s)
        chmod +x ($bin | path join $s)
    }
    $copy | path join persona-dispatcher.nu
}

# The calls one event made (an `up` of IFACE unless args say otherwise), from a lockdown marker as at boot.
def event [dir: path, script: path, policy: any, trusted: bool, args: list<string> = []]: nothing -> list<string> {
    let root = $dir | path join root
    rm --force ($dir | path join calls) ($root | path join run persona-tor) ($root | path join etc NetworkManager untrusted-policy)
    touch ($root | path join run persona-lockdown)
    if $policy != null { $"($policy)\n" | save --force ($root | path join etc NetworkManager untrusted-policy) }
    (if $trusted { $"($IFACE)\n" } else { "" }) | save --force ($root | path join run trusted-network)
    let r = with-env {PATH: ([($dir | path join bin)] ++ $env.PATH), CONNECTION_UUID: "test-uuid"} {
        ^nu --no-config-file -I $LIB $script ...(if ($args | is-empty) { [$IFACE up] } else { $args }) | complete
    }
    assert equal $r.exit_code 0 $"dispatcher failed \(policy ($policy), trusted ($trusted)\): ($r.stderr)"
    let calls = $dir | path join calls
    if ($calls | path exists) { open --raw $calls | lines } else { [] }
}

# The units a verb named, flags dropped, sorted.
def units [calls: list<string>, verb: string]: nothing -> list<string> {
    $calls | where ($it | str starts-with $"systemctl ($verb) ") | each { split row " " | skip 2 } | flatten
    | where not ($it | str starts-with "-") | sort
}

def main [] {
    let dir = mktemp --directory --tmpdir dot-persona-test-XXXXXX
    let script = stage $dir
    let cases = [
        [what policy trusted started stopped];
        ["no policy file, foreign" null false $LOCKDOWN [avahi-daemon.socket]]
        ["an unknown policy, foreign" bogus false $LOCKDOWN [avahi-daemon.socket]]
        ["lockdown-tor, foreign" lockdown-tor false $LOCKDOWN [avahi-daemon.socket]]
        ["lockdown-tor, trusted" lockdown-tor true [avahi-daemon.socket fw-egress.service fw-inbound.service] []]
        ["no policy file, trusted" null true [avahi-daemon.socket fw-egress.service fw-inbound.service] []]
        ["firewall-only, foreign" firewall-only false [fw-lockdown.service] [avahi-daemon.socket fw-egress.service]]
        ["firewall-only, trusted" firewall-only true [avahi-daemon.socket fw-inbound.service] [fw-egress.service]]
        ["off, foreign" off false [avahi-daemon.socket fw-inbound.service] [fw-egress.service]]
    ]
    for c in $cases {
        let calls = event $dir $script $c.policy $c.trusted
        let started = units $calls start
        # the nas mount follows home, which no case is
        let stopped = units $calls stop | where $it != mnt-homelab.mount
        assert equal $started ($c.started | sort) $"($c.what): started ($started | to nuon), wants ($c.started | to nuon)"
        assert equal $stopped ($c.stopped | sort) $"($c.what): stopped ($stopped | to nuon), wants ($c.stopped | to nuon)"
        let v6 = $calls | where ($it | str contains $"net.ipv6.conf.($IFACE).disable_ipv6=") | get --optional 0
        let v6_off = ($v6 | default "" | str ends-with "=1")
        let wants_off = not $c.trusted and $c.policy not-in [firewall-only off]
        assert equal $v6_off $wants_off $"($c.what): ipv6 on the link ($v6)"
    }
    # the foreign link's down (its node gone) lifts the lockdown, and with it ipv6 off on the trusted link left
    let calls = event $dir $script lockdown-tor true [eth8 down]
    assert ($"sysctl -wq net.ipv6.conf.($IFACE).disable_ipv6=0" in $calls) (
        $"lockdown lifted by a down: ipv6 stays off on ($IFACE): ($calls | to nuon)"
    )
    # off trusts every network: a portal's end gives the link back its resolver as on any up
    let calls = event $dir $script off false [$IFACE portal-end]
    let foreign = $"resolvectl default-route ($IFACE) no" in $calls
    assert (not $foreign and $"resolvectl dnsovertls ($IFACE) opportunistic" in $calls) (
        $"off, portal end: foreign dns on ($IFACE): ($calls | to nuon)"
    )
    rm --recursive --force $dir
}

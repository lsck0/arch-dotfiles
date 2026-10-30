#!/usr/bin/env -S nu --no-config-file

const SCRIPTS = path self | path expand | path dirname
use ($SCRIPTS | path join lib usage.nu) [die]

const NETNS = "protonvpn"
const NETNS_RUN = "/usr/local/lib/protonvpn-netns/run"

# Run a command in the fail-closed protonvpn netns: with the tunnel down it refuses, never the real link.
def --wrapped main [...command: string]: nothing -> nothing {
    if ($command | get --optional 0) in ["-h" "--help"] { print "usage: vpn <command...>: run it in the fail-closed protonvpn netns"; return }
    if ($command | is-empty) { die --misuse "the following arguments are required: command" }
    if (do { ^ip netns identify } | complete | get stdout | str trim) == $NETNS { exec ...$command }
    exec sudo -n $NETNS_RUN ...$command
}

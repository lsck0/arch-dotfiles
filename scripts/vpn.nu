#!/usr/bin/env -S nu --no-config-file

const NETNS = "protonvpn"
const NETNS_RUN = "/usr/local/lib/protonvpn-netns/run"

# Run a command in the fail-closed protonvpn netns: with the tunnel down it refuses, never the real link.
def --wrapped main [...command: string]: nothing -> nothing {
    if ($command | is-empty) {
        print --stderr "usage: vpn <command> [args...]"
        exit 2
    }
    # a nested call is already inside
    if (do { ^ip netns identify } | complete | get stdout | str trim) == $NETNS { exec ...$command }
    exec sudo -n $NETNS_RUN ...$command
}

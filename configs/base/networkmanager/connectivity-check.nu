#!/usr/bin/nu --no-config-file
# NM dispatcher, after 70-home-network: NM's connectivity check resolves connectivitycheck.gstatic.com, which the home
# split-horizon DNS (default-route off: 80-homelab-routes) cannot answer, so at home NM sits at LIMITED: a false "No
# internet" in the bar, and timezone-auto waits for a FULL that never comes. off on a home link, on everywhere else so
# captive-portal detection works; on is the resting state, so a failure here never leaves it off on an untrusted
# network. a plain-http probe to an ip literal is no alternative: portmaster/nftables drops it

const HOME_NETWORK = "/run/home-network"
const NM = "org.freedesktop.NetworkManager"
const NM_PATH = "/org/freedesktop/NetworkManager"
const PROPERTY = "ConnectivityCheckEnabled"

def main [iface: string = "", action: string = ""]: nothing -> nothing {
    if $action not-in [up down] { return }
    let home = ($HOME_NETWORK | path exists) and (open --raw $HOME_NETWORK | is-not-empty)
    let want = if $home { "false" } else { "true" }
    let current = do { ^busctl get-property $NM $NM_PATH $NM $PROPERTY } | complete | get stdout | str trim
        | split row " " | get --optional 1
    if $current != $want { do { ^busctl set-property $NM $NM_PATH $NM $PROPERTY b $want } | complete | ignore }
}

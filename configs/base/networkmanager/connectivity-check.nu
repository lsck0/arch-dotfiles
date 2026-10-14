#!/usr/bin/nu --no-config-file
# NM dispatcher: the home split-horizon dns cannot resolve NM's probe (a false LIMITED), so the check is off at home only
# not a plain-http probe to an ip literal: portmaster drops it

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

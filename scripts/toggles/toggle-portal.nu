#!/usr/bin/env -S nu --no-config-file
# The persona dispatcher's captive portal window on the non-home links: on opens it, off ends it early.
use lib.nu [switch-run root-run]

const DISPATCHER = "/etc/NetworkManager/dispatcher.d/90-anonymous-persona"
const HOME_NETWORK = "/run/home-network"
const PORTAL_TIMERS = "persona-portal-*.timer"

def home-links []: nothing -> list<string> {
    if ($HOME_NETWORK | path exists) { open --raw $HOME_NETWORK | lines } else { [] }
}

# The connected physical links the dispatcher treats as foreign; toggle-root decides the same on its own.
def foreign-links []: nothing -> list<string> {
    let home = home-links
    ^nmcli -t -f DEVICE,STATE device | lines | parse --regex '^(?<dev>[^:]*):(?<state>.*)$'
    | where {|l| $l.state == connected and $l.dev not-in $home }
    | where {|l| $"/sys/class/net/($l.dev)/device" | path exists }
    | get dev
}

def portal-open []: nothing -> bool {
    ^systemctl list-units --type timer --state active --plain --no-legend $PORTAL_TIMERS | str trim | is-not-empty
}

def main [action: string = "toggle", --json] {
    switch-run {
        label: "Captive portal"
        is-on: {|| portal-open }
        on: {|| root-run portal on }
        off: {|| root-run portal off }
        available: {|| ($DISPATCHER | path exists) and ((portal-open) or (foreign-links | is-not-empty)) }
    } $action --json=$json
}

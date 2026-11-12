#!/usr/bin/env -S nu --no-config-file
# The persona dispatcher's captive portal window on the untrusted links: on opens it, off ends it early.
use lib.nu [switch-run root-run trusted-links]

const DISPATCHER = "/etc/NetworkManager/dispatcher.d/90-anonymous-persona"
const PORTAL_TIMERS = "persona-portal-*.timer"

# The connected physical links the dispatcher treats as foreign; toggle-root decides the same on its own.
def foreign-links []: nothing -> list<string> {
    let trusted = trusted-links
    ^nmcli -t -f DEVICE,STATE device | lines | parse --regex '^(?<dev>[^:]*):(?<state>.*)$'
    | where {|l| $l.state == connected and $l.dev not-in $trusted }
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

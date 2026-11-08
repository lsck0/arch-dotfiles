#!/usr/bin/nu --no-config-file
# NM dispatcher: home's split-horizon dns cannot resolve NM's probe (a false LIMITED), so the check is off at home only;
# a re-check after the switch clears a LIMITED the probe set before it.
# With the check off NM guesses from the default route (FULL with one, LIMITED without); 80-homelab-routes' dns reapply
# drops the route for a moment, a guess taken then latches LIMITED with no periodic check to clear it, so a LIMITED at
# home asks for one more guess once the route is back. The change can land while the route is still gone and the dhcp
# renewal that puts it back can run before the LIMITED latches, so the change waits a bounded moment for the route.

const HOME_NETWORK = "/run/home-network"
const NM = "org.freedesktop.NetworkManager"
const NM_PATH = "/org/freedesktop/NetworkManager"
const PROPERTY = "ConnectivityCheckEnabled"
const CONNECTIVITY = "Connectivity"
# NMConnectivityState
const LIMITED = "3"
const DHCP_CHANGES = [dhcp4-change dhcp6-change]
# the reapply's dhcp round trip takes well under a second; the dispatcher queue waits behind this at most
const ROUTE_WAIT = 5sec
const ROUTE_POLL = 100ms
const TAG = "75-connectivity-check"

def at-home []: nothing -> bool { ($HOME_NETWORK | path exists) and (open --raw $HOME_NETWORK | is-not-empty) }

# no reply waited for: NM answers only after every probe, which would hold the dispatchers queued behind this one
def recheck []: nothing -> nothing {
    do { ^busctl call --expect-reply=false $NM $NM_PATH $NM CheckConnectivity } | complete | ignore
}

def has-route []: nothing -> bool {
    do { ^ip -4 route show default } | complete | get stdout | str trim | is-not-empty
}

def wait-route []: nothing -> bool {
    let deadline = (date now) + $ROUTE_WAIT
    while not (has-route) {
        if (date now) > $deadline { return false }
        sleep $ROUTE_POLL
    }
    true
}

def note [msg: string]: nothing -> nothing { do { ^logger -t $TAG $msg } | complete | ignore }

def nm-property [name: string]: nothing -> string {
    do { ^busctl get-property $NM $NM_PATH $NM $name } | complete | get stdout | str trim | split row " " | get --optional 1
    | default ""
}

def main [iface: string = "", action: string = ""]: nothing -> nothing {
    if $action == connectivity-change {
        if not (at-home) or $env.CONNECTIVITY_STATE? != LIMITED { return }
        if not (wait-route) { return (note $"($iface): LIMITED, no default route after ($ROUTE_WAIT)") }
        note $"($iface): LIMITED with a default route, rechecking"
        return (recheck)
    }
    if $action in $DHCP_CHANGES {
        if not (at-home) or (nm-property $CONNECTIVITY) != $LIMITED or not (has-route) { return }
        note $"($iface): ($action) while LIMITED, rechecking"
        return (recheck)
    }
    if $action not-in [up down] { return }
    let want = if (at-home) { "false" } else { "true" }
    let current = nm-property $PROPERTY
    if $current == $want { return }
    do { ^busctl set-property $NM $NM_PATH $NM $PROPERTY b $want } | complete | ignore
    note $"($iface) ($action): connectivity check enabled=($want)"
    # turning the check off keeps the last probe's verdict, so the false LIMITED it was turned off for would stay
    recheck
}

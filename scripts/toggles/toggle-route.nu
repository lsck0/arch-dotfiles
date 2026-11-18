#!/usr/bin/env -S nu --no-config-file
# direct, proton, tor or offline; wg0 and the SOCKS pool are not routes. Offline also cycles wg0.
use lib.nu [notify notify-failed cycle-next status-record status-print toggle-run state-get state-set state-file root-run unit-active exclusive-run state-check]
use ../lib/state.nu [xdg]

const ROUTES = {direct: Direct, proton: ProtonVPN, tor: Tor, offline: Offline}
const COUNTRY = "CH"
const TOR_UNIT = "tor-router.service"
const NM_ONLINE_TIMEOUT_S = 30
# the persona dispatcher's mark on a tor it started (lockdown-tor on a foreign network); vpn-up stops that one itself
const DISPATCHER_TOR = "/run/persona-tor"
const PORTMASTER_UNIT = "portmaster.service"
# with the persona dispatcher as a pre-up hook, root stops portmaster before proton0 activates and nothing asks here
const DISPATCHER_PRE_UP = "/etc/NetworkManager/dispatcher.d/pre-up.d/90-anonymous-persona"

def radios []: nothing -> table { ^rfkill -rno TYPE,SOFT | lines | parse "{type} {soft}" }

# networking off alone: a radio unblocked meanwhile (bluetooth for headphones) leaves the machine offline
def offline []: nothing -> bool { (^nmcli networking | complete).stdout == "disabled\n" }

def proton-up []: nothing -> bool { "/sys/class/net/proton0" | path exists }

def current []: nothing -> string {
    if (offline) { "offline" } else if (proton-up) { "proton" } else if (unit-active $TOR_UNIT) { "tor" } else { "direct" }
}

# Stopping a guard lowers, so it is one helper call for all of them: one prompt at most (49-toggles.rules).
def guards-stop [...units: string]: nothing -> nothing {
    let active = $units | where { unit-active $in }
    if ($active | is-not-empty) { root-run guard-stop ...$active }
}

# The persona dispatcher's own decision (its portmaster-on), through the helper: back on behind a raised firewall,
# off where the protonvpn netns tunnel's mark is read. A proton0 going down gets the same from the dispatcher itself.
def portmaster-restore []: nothing -> nothing {
    try { root-run portmaster-restore } catch {|err| print -e $"portmaster left as it is: ($err.msg)" }
}

def proton-connect []: nothing -> nothing {
    let settings = xdg config "Proton VPN" settings.json
    # the app writes every default into settings.json, killswitch 0 included: the value counts, not the key
    if (try { (open $settings).killswitch? | default 0 } catch { 0 }) == 0 {
        ^protonvpn config set kill-switch standard | complete
    }
    if not ($DISPATCHER_PRE_UP | path exists) { guards-stop $PORTMASTER_UNIT }
    let connect = ^protonvpn connect --country $COUNTRY | complete
    let output = $connect.stdout + $connect.stderr
    if $output =~ '(?i)authentication required' {
        notify ProtonVPN "Not signed in, run 'protonvpn signin' in a terminal first" --critical
    }
    if not (proton-up) {
        portmaster-restore
        error make {msg: $"connect failed: ($output)"}
    }
}

def proton-disconnect []: nothing -> nothing {
    if not (proton-up) { return }
    ^protonvpn disconnect o+e> /dev/null
    portmaster-restore
}

def tor-stop []: nothing -> nothing { guards-stop $TOR_UNIT }

# radio types and wg0, persistent: NM's networking off and the rfkill blocks outlast a reboot, rfkill ids may not
def offline-enter []: nothing -> nothing {
    let vpn = (try { toggle-run vpn get | str trim }) == on
    # quiet: the route's own toast says offline; a failure still toasts
    if $vpn {
        try { with-env {TOGGLES_QUIET: "1"} { toggle-run vpn off } } catch { print -e "offline: failed to take wg0 down, continuing" }
    }
    proton-disconnect
    # offline cuts every link below tor anyway: a declined password prompt must not leave the switch half done
    try { tor-stop } catch { print -e "offline: tor keeps running, its links go down anyway" }
    radios | where soft == unblocked | get type | uniq | str join "\n" | save --force (state-file offline-rfkill)
    state-set offline-vpn (if $vpn { "on" } else { "off" })
    ^nmcli networking off
    ^rfkill block all
}

def offline-leave []: nothing -> nothing {
    let saved = state-file offline-rfkill
    # no record: leave every radio as it is, rather than lifting a block set outside this switch
    let types = if ($saved | path exists) { open --raw $saved | lines | where $it != "" } else { [] }
    for type in $types { ^rfkill unblock $type }
    ^nmcli networking on
    let vpn_back = {|| try { with-env {TOGGLES_QUIET: "1"} { toggle-run vpn on o> /dev/null }; true } catch { false } }
    if (state-get offline-vpn) == on and not (do $vpn_back) {
        notify Route "Back online, but the homelab vpn did not come back" --critical
    }
    rm --force $saved (state-file offline-vpn)
}

# only a user-chosen tor stops, after proton0 is up; the dispatcher stops its own
def "main _apply" [route: string, --keep-tor]: nothing -> nothing {
    let from = current
    # still a reply: the bar marks the route busy until the script reports back
    if $route == $from {
        notify Route ($ROUTES | get $route)
        return
    }
    let dispatcher_tor = $DISPATCHER_TOR | path exists
    try {
        # a record outlives networking turned on outside this switch: its radios are still blocked
        if $from == offline or (state-file offline-rfkill | path exists) { offline-leave }
        match $route {
            direct => { proton-disconnect; tor-stop }
            proton => {
                if $from == offline { ^nm-online -qt $NM_ONLINE_TIMEOUT_S | complete | ignore }
                proton-connect
                if not $keep_tor and not $dispatcher_tor {
                    try { tor-stop } catch { notify Route "ProtonVPN is up, tor keeps running beside it" }
                }
            }
            tor => { root-run tor-start; proton-disconnect }
            offline => { offline-enter }
        }
    } catch {|err|
        let cause = $err.msg | str trim | lines | first
        notify-failed Route $cause --to ($ROUTES | get $route) --now ($ROUTES | get (current))
        print -e $err.msg
        exit 1
    }
    notify Route ($ROUTES | get (current))
}

def "main get" [--json] {
    let route = current
    status-print (status-record Route $route --text ($ROUTES | get $route) --states ($ROUTES | columns)) $json
}
def "main set" [route: string, --keep-tor] {
    state-check route $route ($ROUTES | columns)
    exclusive-run Route _apply $route ...(if $keep_tor { [--keep-tor] } else { [] })
}
def "main direct" [] { main set direct }
def "main proton" [--keep-tor] { main set proton --keep-tor=$keep_tor }
def "main tor" [] { main set tor }
def "main offline" [] { main set offline }
# offline is no stop of the cycle: a press too many must not cut the machine off
def "main toggle" [] { main set ($ROUTES | columns | where $it != offline | cycle-next (current)) }
# Route: get [--json] prints the route, set <route> or the route's own name (direct, proton, tor, offline) switches
# to it, toggle takes the next of direct, proton and tor, a bare call toggles.
def main [] { main toggle }

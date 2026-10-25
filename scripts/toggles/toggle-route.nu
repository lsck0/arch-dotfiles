#!/usr/bin/env -S nu --no-config-file
# Where the machine's traffic leaves: direct, through protonvpn, through the tor router, or nowhere (offline). One of
# them at a time; the homelab vpn (wg0, the lab subnets only) and the anonymous SOCKS pool (ports on lo) are not
# routes and stay their own toggles. Offline also takes wg0 down and brings it back on the way out.
use lib.nu [notify cycle-next status-record status-print toggle-run state-get state-set state-file systemctl-guarded unit-active]

const ROUTES = {direct: Direct, proton: ProtonVPN, tor: Tor, offline: Offline}
const COUNTRY = "CH"
const TOR_UNIT = "tor-router.service"
const NM_ONLINE_TIMEOUT_S = 30
# the persona dispatcher's mark on a tor it started (lockdown-tor on a foreign network); vpn-up stops that one itself
const DISPATCHER_TOR = "/run/persona-tor"

def radios []: nothing -> table { ^rfkill -rno ID,SOFT | lines | parse "{id} {soft}" }

def offline []: nothing -> bool {
    (^nmcli networking | complete).stdout == "disabled\n" and (try { radios } catch { [] } | all { $in.soft != unblocked })
}

def proton-up []: nothing -> bool { "/sys/class/net/proton0" | path exists }

def current []: nothing -> string {
    if (offline) { "offline" } else if (proton-up) { "proton" } else if (unit-active $TOR_UNIT) { "tor" } else { "direct" }
}

def portmaster-restore []: nothing -> nothing {
    if (toggle-run firewall get | str trim) != permissive { ^systemctl --no-ask-password start portmaster.service }
}

def proton-connect []: nothing -> nothing {
    let settings = $env.XDG_CONFIG_HOME? | default ($nu.home-dir | path join .config) | path join Proton VPN settings.json
    if not (try { "killswitch" in (open $settings) } catch { false }) {
        ^protonvpn config set kill-switch standard | complete
    }
    ^systemctl --no-ask-password stop portmaster.service | complete
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

def tor-start []: nothing -> nothing { ^systemctl --no-ask-password start $TOR_UNIT }
def tor-stop []: nothing -> nothing { if (unit-active $TOR_UNIT) { systemctl-guarded stop $TOR_UNIT } }

# remembers the radios and whether wg0 was up, so leaving offline restores both
def offline-enter []: nothing -> nothing {
    let vpn = (try { toggle-run vpn get | str trim }) == on
    if $vpn { try { toggle-run vpn off } catch { print -e "offline: failed to take wg0 down, continuing" } }
    proton-disconnect
    tor-stop
    radios | where soft == unblocked | get id | str join "\n" | save --force (state-file offline-rfkill --volatile)
    state-set offline-vpn (if $vpn { "on" } else { "off" }) --volatile
    ^nmcli networking off
    ^rfkill block all
}

def offline-leave []: nothing -> nothing {
    let saved = state-file offline-rfkill --volatile
    let ids = if ($saved | path exists) { open --raw $saved | lines } else { [all] }
    if ($ids | is-not-empty) { ^rfkill unblock ...$ids }
    ^nmcli networking on
    if (state-get offline-vpn --volatile) == on and (try { toggle-run vpn on o> /dev/null; false } catch { true }) {
        notify Route "Back online, but the homelab vpn did not come back" --critical
    }
    rm --force $saved (state-file offline-vpn --volatile)
}

# a vpn connects while tor still carries the link, so tor stops only after proton0 is up, and only a tor the user
# chose: the dispatcher stops the one it started itself on vpn-up, and --keep-tor (auto-vpn, a background service)
# never stops any. A declined stop prompt leaves tor running beside proton, no failed switch.
def apply [route: string, --keep-tor]: nothing -> nothing {
    if $route not-in $ROUTES { error make {msg: $"route must be one of ($ROUTES | columns | str join ', ')"} }
    let from = current
    if $route == $from { return }
    let dispatcher_tor = $DISPATCHER_TOR | path exists
    try {
        if $from == offline { offline-leave }
        match $route {
            direct => { proton-disconnect; tor-stop }
            proton => {
                if $from == offline { ^nm-online -qt $NM_ONLINE_TIMEOUT_S | complete | ignore }
                proton-connect
                if not $keep_tor and not $dispatcher_tor {
                    try { tor-stop } catch { notify Route "ProtonVPN is up, tor keeps running beside it" }
                }
            }
            tor => { tor-start; proton-disconnect }
            offline => { offline-enter }
        }
    } catch {|err|
        notify Route $"Switch to ($ROUTES | get $route) failed, now ($ROUTES | get (current))" --critical
        print -e $err.msg
        exit 1
    }
    notify Route ($ROUTES | get (current))
}

def "main get" [--json] {
    let route = current
    status-print (status-record Route $route --text ($ROUTES | get $route) --states ($ROUTES | columns)) $json
}
def "main set" [route: string] { apply $route }
def "main direct" [] { apply direct }
def "main proton" [--keep-tor] { apply proton --keep-tor=$keep_tor }
def "main tor" [] { apply tor }
def "main offline" [] { apply offline }
# offline is no stop of the cycle: a press too many must not cut the machine off
def "main toggle" [] { apply ($ROUTES | columns | where $it != offline | cycle-next (current)) }
def main [] { main toggle }

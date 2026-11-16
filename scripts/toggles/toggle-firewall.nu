#!/usr/bin/env -S nu --no-config-file
use lib.nu [notify notify-failed root-run unit-active cycle-next status-record status-print exclusive-run state-check]

const STATES = {permissive: Permissive, default: Default, restrictive: Restrictive}
# one step down per press, so default is never reached through permissive
const CYCLE = [restrictive default permissive]

def index-of [state: string]: list<string> -> int { enumerate | where item == $state | get 0.index }

def current []: nothing -> string {
    if (unit-active fw-lockdown.service) { "restrictive" } else if (unit-active fw-inbound.service) { "default" } else { "permissive" }
}

# one root call, so one prompt at most; from permissive, default only tightens and has its own unprompted verb
# (49-toggles.rules)
def "main _apply" [state: string]: nothing -> nothing {
    let from = current
    let verb = if $state == default and $from == permissive { "raise-default" } else { $state }
    try { root-run firewall $verb } catch {|err|
        notify-failed Firewall $err.msg --to ($STATES | get $state) --now ($STATES | get (current))
        exit 1
    }
    let now = current
    if ($CYCLE | index-of $now) > ($CYCLE | index-of $from) {
        notify Firewall $"Lowered to ($STATES | get $now)" --critical
    } else {
        notify Firewall ($STATES | get $now)
    }
}

# portmaster and the nft table should agree; the text says so when they don't
def "main get" [--json] {
    let state = current
    let portmaster = unit-active portmaster.service
    let suffix = if $state != permissive and not $portmaster {
        " (Portmaster off)"
    } else if $state == permissive and $portmaster {
        " (Portmaster on)"
    } else {
        ""
    }
    status-print (status-record Firewall $state --text $"($STATES | get $state)($suffix)" --states ($STATES | columns)) $json
}

def "main toggle" [] { exclusive-run Firewall _apply ($CYCLE | cycle-next (current)) }
def "main set" [state: string] {
    state-check "firewall state" $state ($STATES | columns)
    exclusive-run Firewall _apply $state
}

def "main permissive" [] { main set permissive }
def "main default" [] { main set default }
def "main restrictive" [] { main set restrictive }
# Firewall: get [--json] prints the state, set <state> or the state's own name (permissive, default, restrictive)
# switches to it, toggle goes one step down (restrictive, default, permissive), a bare call toggles.
def main [] { main toggle }

#!/usr/bin/env -S nu --no-config-file
use lib.nu [notify root-run unit-active cycle-next status-record status-print exclusive-run]

const STATES = {permissive: Permissive, default: Default, restrictive: Restrictive}
# one step down per press, so default is never reached through permissive
const CYCLE = [restrictive default permissive]

def current []: nothing -> string {
    if (unit-active fw-lockdown.service) { "restrictive" } else if (unit-active fw-inbound.service) { "default" } else { "permissive" }
}

# one root call, so one prompt at most; from permissive, default only tightens and has its own unprompted verb
# (49-toggles.rules)
def "main _apply" [state: string]: nothing -> nothing {
    let verb = if $state == default and (current) == permissive { "raise-default" } else { $state }
    try { root-run firewall $verb } catch {
        notify Firewall $"Switch failed, now ($STATES | get (current))" --critical
        exit 1
    }
    notify Firewall ($STATES | get (current))
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
    if $state not-in $STATES { error make {msg: $"firewall state is one of ($STATES | columns | str join ', ')"} }
    exclusive-run Firewall _apply $state
}

def "main permissive" [] { main set permissive }
def "main default" [] { main set default }
def "main restrictive" [] { main set restrictive }
def main [] { main toggle }

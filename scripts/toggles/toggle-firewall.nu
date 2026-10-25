#!/usr/bin/env -S nu --no-config-file
use lib.nu [notify root-run unit-active cycle-next]

const STATES = {permissive: Permissive, default: Default, restrictive: Restrictive}

def current []: nothing -> string {
    if (unit-active fw-lockdown.service) { "restrictive" } else if (unit-active fw-inbound.service) { "default" } else { "permissive" }
}

# one root call, so one password prompt at most (49-toggles.rules)
def apply [state: string]: nothing -> nothing {
    try { root-run firewall $state } catch {
        notify Firewall $"Switch failed, now ($STATES | get (current))" --critical
        exit 1
    }
    notify Firewall ($STATES | get (current))
}

def "main get" [] { current }

# portmaster and the nft table should agree; say so when they don't
def "main label" [] {
    let state = current
    let portmaster = unit-active portmaster.service
    let suffix = if $state != permissive and not $portmaster {
        " (Portmaster off)"
    } else if $state == permissive and $portmaster {
        " (Portmaster on)"
    } else {
        ""
    }
    $"(if $state == permissive { '○' } else { '●' }) Firewall: ($STATES | get $state)($suffix)"
}

# a press while a switch waits on its authentication is dropped, not queued behind it
def "main toggle" [] {
    let lock = $env.XDG_RUNTIME_DIR | path join toggle-firewall.lock
    let run = ^flock --nonblock --conflict-exit-code 75 $lock nu --no-config-file $env.CURRENT_FILE _toggle | complete
    if $run.exit_code not-in [0 75] { exit $run.exit_code }
}

def "main _toggle" [] { apply ($STATES | columns | cycle-next (current)) }
def "main set" [state: string] {
    if $state not-in $STATES { error make {msg: $"firewall state is one of ($STATES | columns | str join ', ')"} }
    apply $state
}

def "main permissive" [] { apply permissive }
def "main default" [] { apply default }
def "main restrictive" [] { apply restrictive }
def main [] { main toggle }

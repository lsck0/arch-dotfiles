#!/usr/bin/env -S nu --no-config-file
use lib.nu [notify root-run systemctl-guarded unit-active cycle-next]

const STATES = {permissive: Permissive, default: Default, restrictive: Restrictive}

def current []: nothing -> string {
    if (unit-active fw-lockdown.service) { "restrictive" } else if (unit-active fw-inbound.service) { "default" } else { "permissive" }
}

# portmaster's connmark restore clobbers protonvpn's wireguard fwmark, so toggle-protonvpn owns it while proton0 is up
def portmaster-start []: nothing -> nothing {
    if not ("/sys/class/net/proton0" | path exists) { ^systemctl --no-ask-password start portmaster.service }
}

def apply [state: string]: nothing -> nothing {
    try {
        match $state {
            # conflicts with fw-lockdown, which systemd stops first; from restrictive that lowers it, so polkit asks
            default => { systemctl-guarded start fw-inbound.service; portmaster-start }
            restrictive => { ^systemctl --no-ask-password start fw-lockdown.service; portmaster-start }
            permissive => { systemctl-guarded stop fw-inbound.service fw-lockdown.service portmaster.service }
        }
        root-run firewall-chosen
    } catch {
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

def "main toggle" [] { apply ($STATES | columns | cycle-next (current)) }
def "main set" [state: string] {
    if $state not-in $STATES { error make {msg: $"firewall state is one of ($STATES | columns | str join ', ')"} }
    apply $state
}

def "main permissive" [] { apply permissive }
def "main default" [] { apply default }
def "main restrictive" [] { apply restrictive }
def main [] { main toggle }

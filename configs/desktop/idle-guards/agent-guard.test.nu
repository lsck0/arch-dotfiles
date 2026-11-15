#!/usr/bin/env -S nu --no-config-file
# the agent guard's inhibitors by power source: the lid switch is held on mains only, and a closed, undocked notebook
# on battery holds nothing.
use agent-guard.nu [inhibits-wanted]

def fail [msg: string] { error make {msg: $"agent-guard.test: ($msg)"} }

def main [] {
    let cases = [
        [name on_battery lid_closed docked want];
        [mains false false false [sleep handle-lid-switch]]
        [mains-lid-closed false true false [sleep handle-lid-switch]]
        [battery-lid-open true false false [sleep]]
        [battery-lid-closed-docked true true true [sleep]]
        [battery-lid-closed-undocked true true false []]
    ]
    for c in $cases {
        let got = inhibits-wanted ($c | select on_battery lid_closed docked)
        if $got != $c.want { fail $"($c.name): ($got | to nuon)" }
    }
}

#!/usr/bin/env -S nu --no-config-file
# the agent guard's inhibitors by power source: the lid switch is held on mains only, and a closed, undocked notebook
# on battery holds nothing; a subagent count whose stop hook never ran expires with its claim.
use agent-guard.nu [claim-of inhibits-wanted session-busy]

use std/assert

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
        assert equal $got $c.want $c.name
    }

    let dir = mktemp --directory
    claim-of ($nu.pid | into string) | save ($dir | path join s.pid)
    "1" | save ($dir | path join s.agents)
    assert (session-busy $dir s) "a fresh subagent count is idle"
    ^touch --date "1 hour ago" ($dir | path join s.pid)
    assert (not (session-busy $dir s)) "an orphaned subagent count stays busy"
    rm --recursive $dir
}

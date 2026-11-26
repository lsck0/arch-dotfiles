#!/usr/bin/env -S nu --no-config-file
# the bar options' choices are exactly the widgets plugins/bar/widgets holds

use mod.nu [BAR_WIDGETS]

const HERE = path self .
const WIDGETS = $HERE | path join config/plugins/bar/widgets
const NOT_WIDGETS = [BarSection]

def main [] {
    let found = glob ($WIDGETS | path join "*.qml") | each { path parse | get stem } | where $it not-in $NOT_WIDGETS | sort
    let listed = $BAR_WIDGETS | sort
    if $found != $listed {
        let missing = $found | where $it not-in $listed
        let stale = $listed | where $it not-in $found
        error make {msg: $"BAR_WIDGETS out of date: missing ($missing | str join ', '), stale ($stale | str join ', ')"}
    }
}

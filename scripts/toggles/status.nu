#!/usr/bin/env -S nu --no-config-file
# every toggle-*.nu as json {name, on, setting, label}: the one walker behind menu.nu and quickshell's settings window.
# a label starting with ● is on, ○ is off, anything else (font, scale) is a setting and reads as off
use lib.nu [TOGGLES_DIR]

def main [] {
    glob ($TOGGLES_DIR | path join toggle-*.nu) | par-each {|script|
        let name = $script | path parse | get stem | str replace --regex '^toggle-' ''
        let reply = ^$script label | complete
        let line = if $reply.exit_code == 0 { $reply.stdout | lines | get 0? | default "" } else { $"○ ($name) \(error\)" }
        {
            name: $name
            on: ($line starts-with "●")
            setting: ($line !~ '^[●○] ')
            label: ($line | str replace --regex '^[●○] ' '' | str replace --regex ' \((on|off)\)$' '')
        }
    } | sort-by name | to json --raw
}

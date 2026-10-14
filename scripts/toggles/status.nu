#!/usr/bin/env -S nu --no-config-file
# the one walker behind menu.nu and quickshell's settings window
use lib.nu [TOGGLES_DIR]

const OPTIONS_VERB = 'def "main options"'

# --options adds the rows of each script that answers `options`, which only the settings window edits
def main [--options] {
    glob ($TOGGLES_DIR | path join toggle-*.nu) | par-each {|script|
        let name = $script | path parse | get stem | str replace --regex '^toggle-' ''
        let reply = ^$script label | complete
        let line = if $reply.exit_code == 0 { $reply.stdout | lines | get 0? | default "" } else { $"○ ($name) \(error\)" }
        let toggle = {
            name: $name
            on: ($line starts-with "●")
            setting: ($line !~ '^[●○] ')
            label: ($line | str replace --regex '^[●○] ' '' | str replace --regex ' \((on|off)\)$' '')
        }
        if $options and (open --raw $script | str contains $OPTIONS_VERB) {
            let rows = ^$script options | complete
            $toggle | insert options (if $rows.exit_code == 0 { $rows.stdout | from json } else { [] })
        } else {
            $toggle
        }
    } | sort-by name | to json --raw
}

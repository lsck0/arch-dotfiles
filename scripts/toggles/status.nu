#!/usr/bin/env -S nu --no-config-file
# Every toggle's status record (`get --json`, lib.nu's status-record) as one JSON list, sorted by name.
use lib.nu [TOGGLES_DIR]

const OPTIONS_VERB = 'def "main options"'

# names: only those toggles (the network panel's); --options adds the rows of each script that answers `options`,
# which only the settings window edits
def main [...names: string, --options] {
    let scripts = if ($names | is-empty) {
        glob ($TOGGLES_DIR | path join toggle-*.nu)
    } else {
        $names | each {|name| $TOGGLES_DIR | path join $"toggle-($name).nu" }
    }
    $scripts | par-each {|script|
        let name = $script | path parse | get stem | str replace --regex '^toggle-' ''
        let reply = ^$script get --json | complete
        # empty stdout parses as null without raising: a toggle that broke shows as an error, not as nothing
        let parsed = if $reply.exit_code == 0 { try { $reply.stdout | from json } catch { null } }
        let toggle = $parsed | default {name: $name, label: $name, state: error, text: error, states: [], on: false, available: true}
        if $options and (open --raw $script | str contains $OPTIONS_VERB) {
            let rows = ^$script options | complete
            $toggle | insert options (if $rows.exit_code == 0 { $rows.stdout | from json } else { [] })
        } else {
            $toggle
        }
    } | sort-by name | to json --raw
}

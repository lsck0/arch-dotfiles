#!/usr/bin/env -S nu --no-config-file
use lib.nu [switch-run toggle-run state-get state-set state-file]

const PARTS = [dnd keep-awake nightlight]
const GRADING_PRESET = "grayscale"

def main [action: string = "toggle"] {
    let previous = state-file focus-previous
    switch-run {
        label: "Focus mode"
        is-on: {|| (state-get focus) == on }
        on: {||
            # a second on would record the focus scene itself as the state to restore
            if (state-get focus) == on { return }
            let states = $PARTS | append color-grading | each {|name|
                {name: $name, state: (try { toggle-run $name get | str trim } catch { "off" })}
            }
            $states | to nuon | save --force $previous
            $states | where name in $PARTS and state != on | each {|part| try { toggle-run $part.name on o+e> /dev/null } }
            try { toggle-run color-grading set $GRADING_PRESET o+e> /dev/null }
            state-set focus on
        }
        off: {||
            let states = try { open --raw $previous | from nuon } catch { [] }
            $PARTS | where {|name| ($states | where name == $name | get state.0? | default off) != on } | each {|name|
                try { toggle-run $name off o+e> /dev/null }
            }
            let preset = $states | where name == color-grading | get state.0? | default default
            try { toggle-run color-grading set $preset o+e> /dev/null }
            rm --force $previous
            state-set focus off
        }
    } $action
}

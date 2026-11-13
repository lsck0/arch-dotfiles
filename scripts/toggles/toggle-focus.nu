#!/usr/bin/env -S nu --no-config-file
use lib.nu [switch-run toggle-run state-get state-set state-file]

const PARTS = [dnd keep-awake nightlight]
const GRADING_PRESET = "grayscale"

def main [action: string = "toggle", --json] {
    let previous = state-file focus-previous
    switch-run {
        label: "Focus mode"
        is-on: {|| (state-get focus) == on }
        on: {||
            if (state-get focus) == on { return }
            let states = $PARTS | append color-grading | each {|name|
                {name: $name, state: (try { toggle-run $name get | str trim } catch { "off" })}
            }
            $states | to nuon | save --force $previous
            # quiet: each part's toast would land in history under the dnd it turns on, then all pop up on leaving
            with-env {TOGGLES_QUIET: "1"} {
                $states | where name in $PARTS and state != on | each {|part| try { toggle-run $part.name on o+e> /dev/null } }
                try { toggle-run color-grading set $GRADING_PRESET o+e> /dev/null }
            }
            state-set focus on
        }
        off: {||
            let states = try { open --raw $previous | from nuon } catch { [] }
            let preset = $states | where name == color-grading | get state.0? | default off
            let stuck = with-env {TOGGLES_QUIET: "1"} {
                let failed = $PARTS | where {|name| ($states | where name == $name | get state.0? | default off) != on }
                    | where {|name| try { toggle-run $name off o+e> /dev/null; false } catch { true } }
                let grading = try { toggle-run color-grading set $preset o+e> /dev/null; [] } catch { [color-grading] }
                $failed ++ $grading
            }
            # a part that stayed on keeps focus on and its restore record, so the next off tries it again
            if ($stuck | is-not-empty) { error make {msg: $"focus mode: still on: ($stuck | str join ', ')"} }
            rm --force $previous
            state-set focus off
        }
    } $action --json=$json
}

#!/usr/bin/env -S nu --no-config-file
use lib.nu [switch-run shell-call]

# Do not disturb: get [--json] prints the state, on, off or toggle switches it, a bare call toggles.
def main [action: string = "toggle", --json] {
    switch-run {
        label: "Do not disturb"
        is-on: {|| (shell-call notifications isDnd | str trim) == on }
        on: {|| shell-call notifications setDnd "true" o> /dev/null }
        off: {|| shell-call notifications setDnd "false" o> /dev/null }
    } $action --json=$json
}

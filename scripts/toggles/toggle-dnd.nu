#!/usr/bin/env -S nu --no-config-file
# quickshell's notifications service owns dnd; silenced notifications still land in its history
use lib.nu [switch-run quickshell-call]

def main [action: string = "toggle"] {
    switch-run {
        label: "Do Not Disturb"
        is-on: {|| (quickshell-call notifications isDnd | str trim) == on }
        on: {|| quickshell-call notifications setDnd "true" o> /dev/null }
        off: {|| quickshell-call notifications setDnd "false" o> /dev/null }
    } $action
}

#!/usr/bin/env -S nu --no-config-file
use lib.nu [switch-run root-run unit-active unit-exists]

# Ollama: get [--json] prints the state, on, off or toggle switches it, a bare call toggles. Socket-activated: the
# socket is the switch, or the next request starts it again.
def main [action: string = "toggle", --json] {
    switch-run {
        label: Ollama
        available: {|| unit-exists ollama.socket }
        is-on: {|| unit-active ollama.socket }
        on: {|| root-run ollama on }
        off: {|| root-run ollama off }
    } $action --json=$json
}

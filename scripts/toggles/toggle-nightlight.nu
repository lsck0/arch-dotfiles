#!/usr/bin/env -S nu --no-config-file
use lib.nu [switch-run]

const GRADING = path self ../../configs/desktop/color-grading/scripts/color-grading.py

# Night light: get [--json] prints the state, on, off or toggle switches it, a bare call toggles.
def main [action: string = "toggle", --json] {
    switch-run {
        label: "Night light"
        is-on: {|| (^$GRADING get nightlight | str trim) == on }
        on: {|| ^$GRADING set nightlight on }
        off: {|| ^$GRADING set nightlight off }
    } $action --json=$json
}

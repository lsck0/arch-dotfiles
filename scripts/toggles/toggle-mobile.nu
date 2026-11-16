#!/usr/bin/env -S nu --no-config-file
use lib.nu [switch-run radio-switch]

# Mobile: get [--json] prints the state, on, off or toggle switches it, a bare call toggles.
def main [action: string = "toggle", --json] { switch-run (radio-switch Mobile wwan) $action --json=$json }

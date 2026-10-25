#!/usr/bin/env -S nu --no-config-file
use lib.nu [switch-run radio-switch]

def main [action: string = "toggle", --json] { switch-run (radio-switch Mobile wwan) $action --json=$json }

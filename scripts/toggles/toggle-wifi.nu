#!/usr/bin/env -S nu --no-config-file
use lib.nu [switch-run radio-switch]

def main [action: string = "toggle"] { switch-run (radio-switch Wi-Fi wifi) $action }

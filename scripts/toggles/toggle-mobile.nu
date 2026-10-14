#!/usr/bin/env -S nu --no-config-file
# needs ModemManager, enabled with a modem in networkmanager/system.sh
use lib.nu [switch-run radio-switch]

def main [action: string = "toggle"] { switch-run (radio-switch Mobile wwan) $action }

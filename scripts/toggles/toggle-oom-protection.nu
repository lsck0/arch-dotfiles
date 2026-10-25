#!/usr/bin/env -S nu --no-config-file
use lib.nu [switch-run service-switch]

def main [action: string = "toggle", --json] { switch-run (service-switch "OOM Protection" systemd-oomd.service) $action --json=$json }

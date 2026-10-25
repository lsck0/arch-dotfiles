#!/usr/bin/env -S nu --no-config-file
use lib.nu [switch-run root-run]
use ../lib/profile.nu [profile-has]
use ../lib/platform.nu [platform-load]

const REPO = path self ../..

def main [action: string = "toggle", --json] {
    switch-run {
        label: "Homelab VPN"
        is-on: {|| "/sys/class/net/wg0" | path exists }
        on: {|| root-run wg up }
        off: {|| root-run wg down }
        # the owner on a machine with a wg0 config; the platform file, since the facts' env vars exist only in a dot run
        available: {|| (profile-has secrets) and ((platform-load $REPO).facts.wireguard | is-not-empty) }
    } $action --json=$json
}


#!/usr/bin/env -S nu --no-config-file
use lib.nu [switch-run root-run]
use ../lib/profile.nu [profile-has]
use ../lib/platform.nu [platform-has]

def main [action: string = "toggle"] {
    switch-run {
        label: "Homelab VPN"
        is-on: {|| "/sys/class/net/wg0" | path exists }
        on: {|| root-run wg up }
        off: {|| root-run wg down }
    } $action
}

# the network panel shows the row only to the owner on a machine that reaches the homelab
def "main available" [] { (profile-has secrets) and (platform-has homelab) }

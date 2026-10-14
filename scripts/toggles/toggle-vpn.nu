#!/usr/bin/env -S nu --no-config-file
use lib.nu [switch-run root-run]

def main [action: string = "toggle"] {
    switch-run {
        label: "Homelab VPN"
        is-on: {|| "/sys/class/net/wg0" | path exists }
        on: {|| root-run wg up }
        off: {|| root-run wg down }
    } $action
}

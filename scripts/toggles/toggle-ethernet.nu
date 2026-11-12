#!/usr/bin/env -S nu --no-config-file
use lib.nu [switch-run]

def main [action: string = "toggle", --json] {
    let device = {||
        (^nmcli -t -f DEVICE,TYPE device | complete).stdout | lines | parse "{device}:{type}" | where type == ethernet
        | get --optional 0.device
    }
    switch-run {
        label: Ethernet
        available: {|| do $device | is-not-empty }
        is-on: {|| (^nmcli -t -f DEVICE,STATE device | lines | parse "{device}:{state}" | where device == (do $device) | get --optional 0.state) == connected }
        on: {|| ^nmcli device connect (do $device) }
        off: {|| ^nmcli device disconnect (do $device) }
    } $action --json=$json
}

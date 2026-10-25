#!/usr/bin/env -S nu --no-config-file
use lib.nu [switch-run]

def main [action: string = "toggle", --json] {
    let device = {|| ^nmcli -t -f DEVICE,TYPE device | lines | parse "{device}:{type}" | where type == ethernet | get device.0 }
    switch-run {
        label: Ethernet
        is-on: {|| (^nmcli -t -f DEVICE,STATE device | lines | parse "{device}:{state}" | where device == (do $device) | get --optional 0.state | default "") == connected }
        on: {|| ^nmcli device connect (do $device) }
        off: {|| ^nmcli device disconnect (do $device) }
    } $action --json=$json
}

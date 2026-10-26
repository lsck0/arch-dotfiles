#!/usr/bin/env -S nu --no-config-file
use lib.nu [switch-run]

def main [action: string = "toggle", --json] {
    let device = {|| ^nmcli -t -f DEVICE,TYPE device | lines | parse "{device}:{type}" | where type == ethernet | get --optional 0.device | default "" }
    switch-run {
        label: Ethernet
        available: {|| (^nmcli -t -f TYPE device | complete).stdout | lines | any { $in == ethernet } }
        is-on: {|| (^nmcli -t -f DEVICE,STATE device | lines | parse "{device}:{state}" | where device == (do $device) | get --optional 0.state | default "") == connected }
        on: {|| ^nmcli device connect (do $device) }
        off: {|| ^nmcli device disconnect (do $device) }
    } $action --json=$json
}

#!/usr/bin/env -S nu --no-config-file
use lib.nu [switch-run]

def main [action: string = "toggle", --json] {
    let link = {||
        (^nmcli -t -f DEVICE,TYPE,STATE device | complete).stdout | lines | parse "{device}:{type}:{state}"
        | where type == ethernet | get --optional 0
    }
    switch-run {
        label: Ethernet
        available: {|| do $link | is-not-empty }
        is-on: {|| (do $link).state? == connected }
        on: {|| ^nmcli device connect (do $link).device }
        off: {|| ^nmcli device disconnect (do $link).device }
    } $action --json=$json
}

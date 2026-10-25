#!/usr/bin/env -S nu --no-config-file
use lib.nu [switch-run]

def main [action: string = "toggle", --json] {
    switch-run {
        label: Bluetooth
        is-on: {|| (^bluetoothctl show | complete).stdout =~ 'Powered: yes' }
        on: {|| ^rfkill unblock bluetooth | complete; ^bluetoothctl power on o> /dev/null }
        off: {|| ^bluetoothctl power off o> /dev/null }
    } $action --json=$json
}

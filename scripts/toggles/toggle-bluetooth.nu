#!/usr/bin/env -S nu --no-config-file
use lib.nu [switch-run]

def main [action: string = "toggle"] {
    switch-run {
        label: Bluetooth
        is-on: {|| (^bluetoothctl show | complete).stdout =~ 'Powered: yes' }
        # power on silently fails on a soft-blocked adapter, which toggle-offline leaves behind
        on: {|| ^rfkill unblock bluetooth | complete; ^bluetoothctl power on o> /dev/null }
        off: {|| ^bluetoothctl power off o> /dev/null }
    } $action
}

#!/usr/bin/env -S nu --no-config-file
use lib.nu [switch-run unit-active]

const SHOW_TIMEOUT_S = 3
const POWER_TIMEOUT_S = 5

def main [action: string = "toggle", --json] {
    switch-run {
        label: Bluetooth
        # bluetoothctl waits forever for a bluetoothd that never started (no adapter), so it runs only with one up
        available: {|| (glob /sys/class/bluetooth/hci* | is-not-empty) and (unit-active bluetooth.service) }
        is-on: {|| (^timeout $SHOW_TIMEOUT_S bluetoothctl show | complete).stdout =~ 'Powered: yes' }
        on: {|| ^rfkill unblock bluetooth | complete; ^timeout $POWER_TIMEOUT_S bluetoothctl power on o> /dev/null }
        off: {|| ^timeout $POWER_TIMEOUT_S bluetoothctl power off o> /dev/null }
    } $action --json=$json
}

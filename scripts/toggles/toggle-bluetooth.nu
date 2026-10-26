#!/usr/bin/env -S nu --no-config-file
use lib.nu [switch-run]

def main [action: string = "toggle", --json] {
    switch-run {
        label: Bluetooth
        # bluetoothctl waits forever for a bluetoothd that never started (no adapter), so it runs only with one up
        available: {|| (glob /sys/class/bluetooth/hci* | is-not-empty) and ((^systemctl is-active --quiet bluetooth.service | complete).exit_code == 0) }
        is-on: {|| (^timeout 3 bluetoothctl show | complete).stdout =~ 'Powered: yes' }
        on: {|| ^rfkill unblock bluetooth | complete; ^timeout 5 bluetoothctl power on o> /dev/null }
        off: {|| ^timeout 5 bluetoothctl power off o> /dev/null }
    } $action --json=$json
}

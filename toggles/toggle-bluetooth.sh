#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")"
source ./lib.sh

# writes live here so menu.sh and keybinds work with the shell down
check() { bluetoothctl show 2>/dev/null | grep -q 'Powered: yes' && echo on || echo off; }

# unblock first: power on silently fails on a soft-blocked adapter (toggle-offline leaves it there)
turn_on() {
    rfkill unblock bluetooth 2>/dev/null || true
    bluetoothctl power on >/dev/null
}
turn_off() { bluetoothctl power off >/dev/null; }

toggle_main bluetooth "Bluetooth" check turn_on turn_off "${1:-toggle}"

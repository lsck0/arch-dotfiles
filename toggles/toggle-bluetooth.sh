#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")"
source ./lib.sh

# Extracted from the quickshell Network widget, which used to run
# `bluetoothctl` inline — the toggle contract wants writes to live here so
# menu.sh and any keybind keep working when the shell is down.
#
# `bluetoothctl show` prints "No default controller available" (and exits
# non-zero) when the adapter is rfkill-blocked or absent, so grepping for
# "Powered: yes" covers blocked/missing/off in one check.
check() { bluetoothctl show 2>/dev/null | grep -q 'Powered: yes' && echo on || echo off; }

# Unblock first: `bluetoothctl power on` silently fails against a soft-blocked
# adapter, which is the state toggle-offline.sh leaves behind.
turn_on() {
    rfkill unblock bluetooth 2>/dev/null || true
    bluetoothctl power on >/dev/null
}
turn_off() { bluetoothctl power off >/dev/null; }

toggle_main bluetooth "Bluetooth" check turn_on turn_off "${1:-toggle}"

#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")"
source ./lib.sh
# WWAN radio via nmcli; needs ModemManager (enabled in networkmanager/link.sh)

check() { [[ "$(nmcli radio wwan 2>/dev/null)" == enabled ]] && echo on || echo off; }
turn_on() { nmcli radio wwan on; }
turn_off() { nmcli radio wwan off; }

toggle_main mobile "Mobile" check turn_on turn_off "${1:-toggle}"

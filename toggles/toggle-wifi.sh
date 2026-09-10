#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")"
source ./lib.sh

# Extracted from the quickshell Network widget, which used to run `nmcli`
# inline. Goes through NetworkManager rather than `rfkill block wifi` so the
# state is the one NM itself reports and restores across reboots; NM does its
# own rfkill handling underneath.
check() { [[ "$(nmcli radio wifi 2>/dev/null)" == enabled ]] && echo on || echo off; }
turn_on() { nmcli radio wifi on; }
turn_off() { nmcli radio wifi off; }

toggle_main wifi "Wi-Fi" check turn_on turn_off "${1:-toggle}"

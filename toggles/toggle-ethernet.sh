#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")"
source ./lib.sh

eth_device() { nmcli -t -f DEVICE,TYPE device | awk -F: '$2=="ethernet"{print $1;exit}'; }

check() { nmcli -t -f TYPE,STATE device | grep -q '^ethernet:connected' && echo on || echo off; }
turn_on() { local dev; dev=$(eth_device); [[ -n "$dev" ]] && nmcli device connect "$dev"; }
turn_off() { local dev; dev=$(eth_device); [[ -n "$dev" ]] && nmcli device disconnect "$dev"; }

toggle_main ethernet "Ethernet" check turn_on turn_off "${1:-toggle}"

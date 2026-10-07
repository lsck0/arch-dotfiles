#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")"
source ./lib.sh

check() { ip link show wg0 &>/dev/null && echo on || echo off; }
turn_on() { toggle_root wg up; }
turn_off() { toggle_root wg down; }

toggle_main vpn "Homelab VPN" check turn_on turn_off "${1:-toggle}"

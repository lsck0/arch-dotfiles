#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")"
source ./lib.sh

check() { ip link show wg0 &>/dev/null && echo on || echo off; }
turn_on() { sudo wg-quick up wg0; }
turn_off() { sudo wg-quick down wg0; }

toggle_main vpn "Homelab VPN" check turn_on turn_off "${1:-toggle}"

#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")"
source ./lib.sh

check() { systemctl is-active --quiet tor-router.service && echo on || echo off; }
turn_on() { sudo systemctl start tor-router.service; }
turn_off() { sudo systemctl stop tor-router.service; }

toggle_main tor "Tor Router" check turn_on turn_off "${1:-toggle}"

#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")"
source ./lib.sh

check() { systemctl is-active --quiet systemd-oomd.service && echo on || echo off; }
turn_on() { sudo systemctl start systemd-oomd.service; }
turn_off() { sudo systemctl stop systemd-oomd.service; }

toggle_main oom-protection "OOM Protection" check turn_on turn_off "${1:-toggle}"

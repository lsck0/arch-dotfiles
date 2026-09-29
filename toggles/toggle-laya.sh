#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")"
source ./lib.sh

check() { systemctl --user is-active --quiet laya-serve.service && echo on || echo off; }
turn_on() { systemctl --user start laya-serve.service; }
turn_off() { systemctl --user stop laya-serve.service; }

toggle_main laya "Laya" check turn_on turn_off "${1:-toggle}"

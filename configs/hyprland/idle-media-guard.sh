#!/usr/bin/env bash

set -euo pipefail

command -v playerctl >/dev/null 2>&1 || exit 0

status=$(playerctl status 2>/dev/null || true)
[[ "$status" == "Playing" ]] && exit 1
exit 0

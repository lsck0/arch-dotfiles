#!/usr/bin/env bash
# hypridle condition_cmd for the lock/suspend listeners in hypridle.conf.
# Exit 0 = proceed with on-timeout (lock/suspend), exit 1 = defer/retry.
# Playing media (movie, music, video call) should never get interrupted by
# an idle-triggered lock or suspend just because there's no keyboard/mouse
# activity — playerctl is the standard MPRIS query for "is anything playing
# right now" across browsers/mpv/spotify/etc.
set -euo pipefail

command -v playerctl >/dev/null 2>&1 || exit 0

status=$(playerctl status 2>/dev/null || true)
[[ "$status" == "Playing" ]] && exit 1
exit 0

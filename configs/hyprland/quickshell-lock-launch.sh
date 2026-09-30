#!/usr/bin/env bash
# route lock requests to the quickshell lock; no-op if already locked

set -euo pipefail

qs_path="${XDG_CONFIG_HOME:-$HOME/.config}/quickshell"

if command -v quickshell >/dev/null 2>&1 \
    && pgrep -x quickshell -u "$USER" >/dev/null 2>&1; then
  state=$(timeout 3s quickshell ipc -p "$qs_path" call lock isLocked 2>/dev/null || true)
  [[ "$state" == "true" ]] && exit 0
  if timeout 5s quickshell ipc -p "$qs_path" call lock lock >/dev/null 2>&1; then
    exit 0
  fi
fi

# no fallback locker: blank and fail rather than fake a lock
notify-send -u critical "lock" "quickshell unreachable, cannot lock" 2>/dev/null || true
hyprctl dispatch "hl.dsp.dpms({ mode = 'off' })" 2>/dev/null || true
exit 1

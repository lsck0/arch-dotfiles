#!/usr/bin/env bash
# Single lock entrypoint: route logind/hypridle lock requests to the quickshell
# matrix lock (ext-session-lock-v1). Idempotent - a no-op if already locked.
# quickshell is the sole locker (hyprlock removed). If it is unreachable we
# cannot lock (WlSessionLock needs it); we blank the screen and exit nonzero
# rather than fake a lock, and hypridle's suspend timer still secures the box.

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

# quickshell unreachable: no fallback locker. Warn, blank the screen, and exit
# nonzero (do not fake a lock). The hypridle suspend timer still secures the box.
notify-send -u critical "lock" "quickshell unreachable, cannot lock" 2>/dev/null || true
hyprctl dispatch dpms off 2>/dev/null || true
exit 1

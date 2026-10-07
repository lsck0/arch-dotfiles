#!/usr/bin/env bash
# route lock requests to the quickshell lock, hyprlock when quickshell is unreachable; no-op if already locked

set -euo pipefail

qs_path="${XDG_CONFIG_HOME:-$HOME/.config}/quickshell"
LOCK_POLL_TRIES=30
LOCK_POLL_INTERVAL=0.1

pgrep -x hyprlock -u "$USER" >/dev/null 2>&1 && exit 0

if command -v quickshell >/dev/null 2>&1 \
    && pgrep -x quickshell -u "$USER" >/dev/null 2>&1; then
  state=$(timeout 3s quickshell ipc -p "$qs_path" call lock isLocked 2>/dev/null || true)
  [[ "$state" == "true" ]] && exit 0
  if timeout 5s quickshell ipc -p "$qs_path" call lock lock >/dev/null 2>&1; then
    # wait for the compositor to grant the lock before returning; as a before_sleep_cmd barrier this
    # keeps the freeze from racing the ext-session-lock handshake, which aborts quickshell mid-suspend
    for _ in $(seq 1 "$LOCK_POLL_TRIES"); do
      [[ "$(timeout 1s quickshell ipc -p "$qs_path" call lock isLocked 2>/dev/null || true)" == "true" ]] && exit 0
      sleep "$LOCK_POLL_INTERVAL"
    done
    # never granted: refused or stuck handshake, fall through to hyprlock
  fi
fi

if command -v hyprlock >/dev/null 2>&1; then
  setsid hyprlock --grace 0 --immediate-render >/dev/null 2>&1 &
  pid=$!
  # hyprlock reports no lock state, so it counts as held once it survives the wait; a refused lock or bad config exits early
  for _ in $(seq 1 "$LOCK_POLL_TRIES"); do
    kill -0 "$pid" 2>/dev/null || break
    sleep "$LOCK_POLL_INTERVAL"
  done
  kill -0 "$pid" 2>/dev/null && exit 0
fi

# no locker left: blank and fail rather than fake a lock
notify-send -u critical "lock" "quickshell and hyprlock unreachable, cannot lock" 2>/dev/null || true
hyprctl dispatch "hl.dsp.dpms({ mode = 'off' })" 2>/dev/null || true
exit 1

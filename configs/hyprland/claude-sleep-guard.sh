#!/usr/bin/env bash
# Mark a claude session busy (working, not idle at the prompt) so the machine won't auto-suspend.

set -euo pipefail

action="${1:?acquire|release}"
sid="${2:-}"
if [ -z "$sid" ]; then
    payload="$(cat 2>/dev/null || true)"
    sid="$(printf '%s' "$payload" | jq -r '.session_id // empty' 2>/dev/null || true)"
    [ -n "$sid" ] || sid="default"
fi

dir="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/claude-busy"
mkdir -p "$dir"

case "$action" in
    # Store the claude PID so the guard can drop the marker if the session dies
    # without releasing (crash/kill), instead of blocking suspend on a time window.
    acquire) echo "$PPID" > "$dir/$sid" ;;
    release) rm -f "$dir/$sid" ;;
    *) echo "usage: claude-sleep-guard acquire|release [session-id]" >&2; exit 2 ;;
esac

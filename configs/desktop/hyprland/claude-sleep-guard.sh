#!/usr/bin/env bash
# mark a claude session busy so the machine won't auto-suspend

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
    # pid lets the guard drop markers of dead sessions
    acquire) echo "$PPID" > "$dir/$sid" ;;
    release) rm -f "$dir/$sid" ;;
    *) echo "usage: claude-sleep-guard acquire|release [session-id]" >&2; exit 2 ;;
esac

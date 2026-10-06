#!/usr/bin/env bash
# mark a claude session busy and hold a systemd sleep inhibitor, so the machine never suspends or
# hibernates mid-run by any path (hypridle idle, logind idle-action, lid close, low battery, manual).
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
marker="$dir/$sid"
holder="$dir/.$sid.hold"

case "$action" in
# pid in the marker lets the hypridle guard and the holder below drop a dead session
acquire)
    echo "$PPID" >"$marker"
    # one inhibitor per session: block mode stops every sleep path, and it self-exits once the marker clears or the session dies, so a crash never leaks the lock
    if ! { [ -f "$holder" ] && kill -0 "$(cat "$holder" 2>/dev/null)" 2>/dev/null; }; then
        setsid systemd-inhibit --what=sleep:handle-lid-switch --who="Claude Code" --why="session working" --mode=block \
            bash -c 'm="$1"; while [ -e "$m" ] && kill -0 "$(cat "$m" 2>/dev/null)" 2>/dev/null; do sleep 5; done' _ "$marker" \
            </dev/null >/dev/null 2>&1 &
        echo "$!" >"$holder"
    fi
    ;;
release)
    rm -f "$marker" "$holder"
    ;;
*)
    echo "usage: claude-sleep-guard acquire|release [session-id]" >&2
    exit 2
    ;;
esac

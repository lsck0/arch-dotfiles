#!/usr/bin/env bash
# keeps the machine awake while a coding agent (claude code, hermes) actually works: a turn in flight or a
# subagent running. an open but idle session holds nothing. called from the agents' hooks with their json on stdin.
#   turn-start | turn-end | subagent-start | subagent-stop   hook events
#   busy                                                      exit 0 while any agent works (hypridle condition)
set -euo pipefail

POLL_SECONDS=5

dir="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/agent-busy"
mkdir -p "$dir"

session_id() {
    local payload sid
    payload=$(cat 2>/dev/null || true)
    sid=$(jq -r '.session_id // empty' <<<"$payload" 2>/dev/null || true)
    echo "${sid:-default}"
}

# a session is busy while its turn flag exists or a subagent count is above zero, and its agent process lives
session_busy() {
    local sid="$1" pid
    pid=$(cat "$dir/$sid.pid" 2>/dev/null || true)
    [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null || return 1
    [[ -e "$dir/$sid.turn" ]] || (($(cat "$dir/$sid.agents" 2>/dev/null || echo 0) > 0))
}

any_busy() {
    local f
    for f in "$dir"/*.pid; do
        [[ -e "$f" ]] || continue
        session_busy "$(basename "$f" .pid)" && return 0
    done
    return 1
}

# one block inhibitor for all agents; it exits by itself once nothing is busy, so a crash never leaks it
holder_ensure() {
    local holder="$dir/.holder"
    [[ -f "$holder" ]] && kill -0 "$(cat "$holder")" 2>/dev/null && return 0
    setsid systemd-inhibit --what=sleep:handle-lid-switch --who="coding agent" --why="agent working" --mode=block \
        "$0" hold </dev/null >/dev/null 2>&1 &
    echo "$!" >"$holder"
}

agents_add() {
    local sid="$1" n
    n=$(($(cat "$dir/$sid.agents" 2>/dev/null || echo 0) + $2))
    ((n > 0)) || n=0
    echo "$n" >"$dir/$sid.agents"
}

action="${1:?turn-start|turn-end|subagent-start|subagent-stop|busy}"
case "$action" in
turn-start | subagent-start)
    sid=$(session_id)
    echo "$PPID" >"$dir/$sid.pid"
    if [[ "$action" == turn-start ]]; then touch "$dir/$sid.turn"; else agents_add "$sid" 1; fi
    holder_ensure
    ;;
turn-end)
    sid=$(session_id)
    rm -f "$dir/$sid.turn"
    ;;
subagent-stop)
    sid=$(session_id)
    agents_add "$sid" -1
    ;;
busy) any_busy ;;
hold) while any_busy; do sleep "$POLL_SECONDS"; done ;;
*)
    echo "usage: agent-guard turn-start|turn-end|subagent-start|subagent-stop|busy" >&2
    exit 2
    ;;
esac

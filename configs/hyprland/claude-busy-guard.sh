#!/usr/bin/env bash
# hypridle condition_cmd: exit 1 (block suspend) while any claude session is actively working.

set -euo pipefail

dir="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/claude-busy"

[ -d "$dir" ] || exit 0

# A marker holds the claude PID. Drop it if that process is gone (crashed or
# killed without releasing), else the session is genuinely working: block suspend.
busy=0
for marker in "$dir"/*; do
    [ -e "$marker" ] || continue
    pid="$(cat "$marker" 2>/dev/null || true)"
    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
        busy=1
    else
        rm -f "$marker" 2>/dev/null || true
    fi
done

[ "$busy" -eq 1 ] && exit 1
exit 0

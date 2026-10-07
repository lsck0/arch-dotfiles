#!/usr/bin/env bash
# holds a sleep inhibitor while any player plays, so the machine never suspends under it; dim and lock still happen, video apps inhibit idle themselves
set -euo pipefail

holder=""
release() {
    [[ -z "$holder" ]] || kill "$holder" 2>/dev/null || true
    holder=""
}
trap release EXIT

# --follow only wakes us on a change; the aggregate is re-read so one paused player cannot release another's hold
while read -r _; do
    if playerctl --all-players status 2>/dev/null | grep -qx Playing; then
        [[ -n "$holder" ]] && kill -0 "$holder" 2>/dev/null && continue
        systemd-inhibit --what=sleep --mode=block --who="media" --why="media playing" sleep infinity &
        holder=$!
    else
        release
    fi
done < <(playerctl --all-players --follow status 2>/dev/null)
# the monitor ending is a failure, so Restart=on-failure brings the guard back
echo "playerctl --follow ended" >&2
exit 1

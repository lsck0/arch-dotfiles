#!/usr/bin/env bash
# holds a sleep inhibitor while an ssh session is in on 2222, so no session idles the machine away under it; locking still happens
set -euo pipefail

SSH_PORT=2222

holder=""
release() {
    [[ -z "$holder" ]] || kill "$holder" 2>/dev/null || true
    holder=""
}
trap release EXIT

# any logind signal (session new, removed or changed) triggers a recheck; gdbus's startup lines give the initial one
while read -r _; do
    if ss -Htn state established "( sport = :${SSH_PORT} )" 2>/dev/null | grep -q .; then
        if [[ -z "$holder" ]] || ! kill -0 "$holder" 2>/dev/null; then
            systemd-inhibit --what=sleep --mode=block --who="sshd" --why="ssh session on ${SSH_PORT}" sleep infinity &
            holder=$!
        fi
    else
        release
    fi
done < <(gdbus monitor --system --dest org.freedesktop.login1)
# the monitor ending is a failure, so Restart=on-failure brings the guard back
echo "gdbus monitor ended" >&2
exit 1

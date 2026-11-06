#!/usr/bin/bash
# pywalfox's native host, skipped for a headless Firefox (playwright, an agent's check): each host takes the one
# per-user socket /tmp/pywalfox_socket_<uid> and deletes it on exit, cutting the desktop Firefox off from theme switches.
# bash builtins only, so the apparmor child profile needs nothing beyond the shell
mapfile -d '' -t argv < "/proc/$PPID/cmdline"
for arg in "${argv[@]}"; do
    [[ $arg == --headless || $arg == -headless ]] && exit 0
done
exec @MAIN@ "$@"

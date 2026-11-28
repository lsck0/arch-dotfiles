#!/usr/bin/bash
# pywalfox's native host, skipped for a headless Firefox (playwright, an agent's check): each host takes the one
# per-user socket /tmp/pywalfox_socket_<uid> and deletes it on exit, cutting the desktop Firefox off from theme switches.
mapfile -d '' -t argv < "/proc/$PPID/cmdline"
for arg in "${argv[@]}"; do
    [[ $arg == --headless || $arg == -headless ]] && exit 0
done
# a second Firefox with a window (another profile, a test instance) does the same: its host cannot bind the socket a
# live host holds, and still deletes it on exit
socket=${TMPDIR:-/tmp}/pywalfox_socket_$UID
if [[ -S $socket ]] && /usr/bin/python -I -c 'import socket, sys; socket.socket(socket.AF_UNIX, socket.SOCK_DGRAM).connect(sys.argv[1])' "$socket" 2> /dev/null; then
    exit 0
fi
# pywalfox reads $XDG_CACHE_HOME/wal/colors.json; the firefox module writes it a copy with the slots solved for
# contrast (pywalfox-slots)
export XDG_CACHE_HOME=@CACHE@
exec @MAIN@ "$@"

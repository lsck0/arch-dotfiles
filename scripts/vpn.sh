#!/usr/bin/env bash
# Run a command in the fail-closed protonvpn netns: with the tunnel down it refuses, never the real link.
set -euo pipefail

NS=protonvpn
RUN=/usr/local/lib/protonvpn-netns/run

case ${1:-} in
    -h | --help)
        echo "usage: vpn <command...>: run it in the fail-closed protonvpn netns"
        exit 0
        ;;
    "")
        echo "vpn: the following arguments are required: command" >&2
        exit 2
        ;;
esac
if [ "$(ip netns identify 2> /dev/null)" = "$NS" ]; then
    exec "$@"
fi
# the namespace's PATH is the system one: resolve here, where the caller's ~/.local/bin counts, and fail as a shell would
cmd=$(command -v "$1") || {
    echo "vpn: $1: command not found" >&2
    exit 127
}
shift
exec sudo -n "$RUN" "$cmd" "$@"

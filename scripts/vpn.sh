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
exec sudo -n "$RUN" "$@"

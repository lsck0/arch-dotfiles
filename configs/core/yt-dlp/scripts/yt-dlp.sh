#!/bin/sh
# yt-dlp through base/protonvpn-netns' shim only, never the bare route.
set -eu

SHIM=/usr/local/bin/yt-dlp

if [ ! -e "$SHIM" ]; then
    echo "yt-dlp: no ProtonVPN namespace on this machine (base/protonvpn-netns), refusing the bare route" >&2
    exit 1
fi
exec "$SHIM" "$@"

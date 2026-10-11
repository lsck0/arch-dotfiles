#!/usr/bin/env bash
# Auto-route yt-dlp through the ProtonVPN tunnel: when proton0 is up (auto-vpn raises it on untrusted networks)
# bind downloads to its address so they can't leak onto the bare interface; at home, where proton0 is down, fall
# back to the normal route. Shadows /usr/bin/yt-dlp via ~/.local/bin (linked by link.sh / link_commands).

args=()
if ip -o link show proton0 >/dev/null 2>&1; then
    ip4=$(ip -4 -o addr show dev proton0 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | head -n1)
    [ -n "$ip4" ] && args+=(--source-address "$ip4")
fi
exec /usr/bin/yt-dlp "${args[@]}" "$@"

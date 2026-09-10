#!/usr/bin/env bash
# One-line system stats for the hyprlock screen (configs/hyprland/hyprlock.conf),
# polled every few seconds via cmd[update:...]. Deliberately local-only: no
# network calls, nothing that can hang or stall a label update while the
# screen is locked. All sources here are /proc or fast, cached-by-the-kernel
# CLI tools (free, uname), so the whole thing runs in a few ms.
set -euo pipefail

nproc_count=$(nproc)
cpu=$(awk -v n="$nproc_count" '{printf "%.0f", $1 * 100 / n}' /proc/loadavg)
mem=$(free -h --si 2>/dev/null | awk '/^Mem:/ {print $3"/"$2}')
up=$(uptime -p | sed -E 's/^up //; s/ hours?/h/; s/ minutes?/m/; s/,//g')
kernel=$(uname -r)

printf '%s   cpu %s%%   mem %s   up %s\n' "$kernel" "$cpu" "$mem" "$up"

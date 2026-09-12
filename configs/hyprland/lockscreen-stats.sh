#!/usr/bin/env bash

set -euo pipefail

nproc_count=$(nproc)
cpu=$(awk -v n="$nproc_count" '{printf "%.0f", $1 * 100 / n}' /proc/loadavg)
mem=$(free -h --si 2>/dev/null | awk '/^Mem:/ {print $3"/"$2}')
up=$(uptime -p | sed -E 's/^up //; s/ hours?/h/; s/ minutes?/m/; s/,//g')
kernel=$(uname -r)

printf '%s   cpu %s%%   mem %s   up %s\n' "$kernel" "$cpu" "$mem" "$up"

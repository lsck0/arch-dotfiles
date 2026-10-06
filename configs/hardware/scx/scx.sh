#!/usr/bin/env bash
# pick the scx_lavd power mode from the power source: ac or no battery is full performance,
# on battery is balanced until 50 percent, then powersave. run execs the scheduler, refresh
# restarts it only when the desired mode changed, so the timer and udev hook are cheap.
set -euo pipefail

CUR=/run/scx-lavd.current

desired_flag() {
    compgen -G '/sys/class/power_supply/BAT*' >/dev/null || { echo --performance; return; }
    local type online
    for type in /sys/class/power_supply/*/type; do
        [[ -f "$type" && "$(<"$type")" == Mains ]] || continue
        online="${type%/type}/online"
        [[ -f "$online" && "$(<"$online")" == 1 ]] && { echo --performance; return; }
    done
    local cap
    cap=$(cat /sys/class/power_supply/BAT*/capacity 2>/dev/null | head -1) || cap=
    ((${cap:-100} < 50)) && echo --powersave || echo --balanced
}

case "${1:-}" in
run)
    flag=$(desired_flag)
    echo "$flag" >"$CUR"
    exec /usr/bin/scx_lavd "$flag"
    ;;
refresh)
    flag=$(desired_flag)
    [[ -f "$CUR" && "$(<"$CUR")" == "$flag" ]] && exit 0
    systemctl restart scx-lavd.service
    ;;
*)
    echo "usage: $(basename "$0") {run|refresh}" >&2
    exit 1
    ;;
esac

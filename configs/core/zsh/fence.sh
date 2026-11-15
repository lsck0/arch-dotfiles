#!/bin/sh
# Run a command at the lowest cpu and oom priority, pinned to the non-v-cache ccd where there is one. sh, not nu: a nu
# script evaluates and requotes its --flag=value arguments, "$@" passes them on untouched.
set -eu

OOM_SCORE_ADJ=1000
NICENESS=19
CPU_WEIGHT=10
CPU_DIR=/sys/devices/system/cpu

l3_kb() {
    read -r size < "$1"
    printf %s "${size%%[!0-9]*}"
}

# The cpus whose l3 is smaller than the largest: the non-v-cache ccd on an x3d part, none on a uniform cpu.
cpus_build() {
    kb_max=0
    for cache in "$CPU_DIR"/cpu[0-9]*/cache/index3/size; do
        [ -r "$cache" ] || continue
        kb=$(l3_kb "$cache")
        if [ "$kb" -gt "$kb_max" ]; then kb_max=$kb; fi
    done
    cpus=
    for cache in "$CPU_DIR"/cpu[0-9]*/cache/index3/size; do
        [ -r "$cache" ] || continue
        if [ "$(l3_kb "$cache")" -lt "$kb_max" ]; then
            cpu=${cache#"$CPU_DIR"/cpu}
            cpus=${cpus:+$cpus,}${cpu%%/*}
        fi
    done
    printf %s "$cpus"
}

if [ $# -eq 0 ]; then
    echo "usage: fence <command> [args...]" >&2
    exit 2
fi
build=$(cpus_build)
set -- nice "-n$NICENESS" "$@"
if [ -n "$build" ]; then
    set -- taskset -c "$build" "$@"
fi
set -- choom -n "$OOM_SCORE_ADJ" -- "$@"
# the scope needs a reachable user manager, which a bare wsl root shell lacks
if systemctl --user show-environment > /dev/null 2>&1; then
    exec systemd-run --user --scope --quiet -p "CPUWeight=$CPU_WEIGHT" "$@"
fi
exec "$@"

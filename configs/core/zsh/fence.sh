#!/bin/sh
# Run a command at the lowest cpu and oom priority, pinned to the non-v-cache ccd where there is one.
set -eu

OOM_SCORE_ADJ=1000
NICENESS=19
CPU_WEIGHT=10
CPU_DIR=/sys/devices/system/cpu

# The cpus whose l3 is smaller than the largest: the non-v-cache ccd on an x3d part, none on a uniform cpu. A line is
# .../cpu<n>/cache/index3/size:<kb>K, so the numbers in it are n, 3 and kb.
cpus_build() {
    grep -H . "$CPU_DIR"/cpu[0-9]*/cache/index3/size 2> /dev/null |
        awk -F '[^0-9]+' '{ kb[$2] = $4; if ($4 > kb_max) kb_max = $4 }
            END { for (cpu in kb) if (kb[cpu] < kb_max) cpus = cpus (cpus == "" ? "" : ",") cpu; printf "%s", cpus }'
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

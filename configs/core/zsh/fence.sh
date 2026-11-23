#!/bin/sh
# Run a heavy command in a memory-capped user scope at the lowest cpu, io and oom priority, pinned to the non-v-cache
# ccd where there is one. FENCE_MEM overrides the memory cap (FENCE_MEM=14G); --cpu-quota <percent> caps cpu time.
# The user manager delegates only cpu, memory and pids, so AllowedCPUs= and IOWeight= would be ignored in the scope:
# taskset and ionice do that part. A killed run leaves a failed run-*.scope: systemctl --user reset-failed.
set -eu

MEMORY_MAX_DEFAULT=16G
MEMORY_SWAP_MAX=1G
OOM_SCORE_ADJ=1000
NICENESS=19
IO_CLASS_IDLE=3
CPU_WEIGHT=10
CPU_DIR=/sys/devices/system/cpu
USAGE="usage: fence [--cpu-quota <percent>] <command...>"

# The cpus whose l3 is smaller than the largest: the non-v-cache ccd on an x3d part, none on a uniform cpu. A line is
# .../cpu<n>/cache/index3/size:<kb>K, so the numbers in it are n, 3 and kb.
cpus_build() {
    grep -H . "$CPU_DIR"/cpu[0-9]*/cache/index3/size 2> /dev/null |
        awk -F '[^0-9]+' '{ kb[$2] = $4; if ($4 > kb_max) kb_max = $4 }
            END { for (cpu in kb) if (kb[cpu] < kb_max) cpus = cpus (cpus == "" ? "" : ",") cpu; printf "%s", cpus }'
}

cpu_quota=
case ${1:-} in
    -h | --help)
        echo "$USAGE: run it memory-capped (FENCE_MEM, default $MEMORY_MAX_DEFAULT) at the lowest cpu, io and oom priority"
        exit 0
        ;;
esac
if [ "${1:-}" = --cpu-quota ]; then
    case "${2:-}" in
        '' | *[!0-9]*)
            echo "$USAGE" >&2
            exit 2
            ;;
    esac
    cpu_quota=$2
    shift 2
fi
if [ $# -eq 0 ]; then
    echo "$USAGE" >&2
    exit 2
fi
set -- nice "-n$NICENESS" "$@"
build=$(cpus_build)
if [ -n "$build" ]; then
    set -- taskset -c "$build" "$@"
fi
set -- choom -n "$OOM_SCORE_ADJ" -- ionice -c "$IO_CLASS_IDLE" "$@"
# the scope needs a reachable user manager, which a bare wsl root shell lacks
if ! systemctl --user show-environment > /dev/null 2>&1; then
    echo "fence: no user manager, running without a memory cap" >&2
    exec "$@"
fi
set -- -p "MemoryMax=${FENCE_MEM:-$MEMORY_MAX_DEFAULT}" -p "MemorySwapMax=$MEMORY_SWAP_MAX" -p "CPUWeight=$CPU_WEIGHT" \
    -- "$@"
if [ -n "$cpu_quota" ]; then
    set -- -p "CPUQuota=$cpu_quota%" "$@"
fi
exec systemd-run --user --scope --quiet "$@"

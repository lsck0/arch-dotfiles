#!/usr/bin/env bash
# run a heavy build off the v-cache ccd, low priority and oom-first, in its own scope: under memory pressure
# systemd-oomd evicts the build, not the terminal, herdr session or agent that started it. a script, not a shell
# function, so agents' non-interactive shells reach it too
# usage: fence <command> [args...]   e.g. fence make -j / fence cargo build / fence ./gradlew build

set -euo pipefail
(($#)) || { echo "usage: fence <command> [args...]" >&2; exit 2; }

# cpus whose l3 is smaller than the largest: the non-v-cache ccd on an x3d part, none on a uniform cpu
declare -A size_of=()
max=0
for cache in /sys/devices/system/cpu/cpu[0-9]*/cache/index3/size; do
    [[ -r "$cache" ]] || continue
    size=$(<"$cache")
    size=${size%%[^0-9]*}
    [[ -n "$size" ]] || continue
    cpu=${cache#/sys/devices/system/cpu/cpu}
    cpu=${cpu%%/*}
    size_of[$cpu]=$size
    ((size > max)) && max=$size
done
build=()
for cpu in "${!size_of[@]}"; do
    ((size_of[$cpu] < max)) && build+=("$cpu")
done

pre=(choom -n 1000 --)
if ((${#build[@]})); then
    pre+=(taskset -c "$(IFS=,; echo "${build[*]}")")
fi
pre+=(nice -n19)
# the cgroup scope needs a reachable user manager, which a bare wsl root shell lacks
if systemctl --user show-environment >/dev/null 2>&1; then
    exec systemd-run --user --scope --quiet -p CPUWeight=10 "${pre[@]}" "$@"
fi
exec "${pre[@]}" "$@"

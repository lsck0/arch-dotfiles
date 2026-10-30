#!/bin/sh
# energy_uj stays root-only (CVE-2020-8694): the bar gets the package draw as whole watts averaged over the interval.
set -eu

rapl=/sys/class/powercap/intel-rapl:0
out=/run/powercap/watts
interval=${1:-10}

read -r range < "$rapl/max_energy_range_uj"
read -r prev < "$rapl/energy_uj"
prev_ns=$(date +%s%N)
while sleep "$interval"; do
    read -r energy < "$rapl/energy_uj"
    now_ns=$(date +%s%N)
    delta=$((energy - prev))
    [ "$delta" -ge 0 ] || delta=$((delta + range))
    dt_ns=$((now_ns - prev_ns))
    # uJ * 1000 / ns is W, rounded half up
    echo $(((delta * 1000 + dt_ns / 2) / dt_ns)) > "$out.new"
    mv -f "$out.new" "$out"
    prev=$energy
    prev_ns=$now_ns
done

#!/usr/bin/env bash
# Streams one JSON line per sample: CPU, memory, iGPU and package power.
#
# LONG-LIVED, not one-shot. This used to be respawned by System.qml every 5
# seconds, which meant a fresh bash plus ~8 forks per sample forever. It now
# runs once and prints a line per interval, read with SplitParser — the same
# shape as the cava and `nmcli monitor` readers.
#
# WHAT THIS HARDWARE CANNOT REPORT. Both are real hardware facts, not gaps,
# and the widget says so rather than showing a plausible zero:
#
#   * CPU/GPU voltage — no hwmon chip here exposes vcore. `sensors -j` has
#     exactly three voltage inputs: the battery (12.175V) and two USB-PD
#     rails (0V, 5V). Package power in watts is reported instead, which is
#     the useful thing people actually want vcore for.
#   * VRAM — this is an Intel UHD 620 iGPU. i915 has no VRAM concept and no
#     sysfs equivalent of AMD's mem_info_vram_used. Emitted as null and
#     gated on `gpuVendor`, so the same script works unmodified if a
#     discrete AMD/NVIDIA card ever appears.
#
# CORRECTION: an earlier version of this comment claimed `intel_gpu_top` was
# not installed. It is (/usr/sbin/intel_gpu_top). The actual blocker is
# `kernel.perf_event_paranoid=2`, which stops it reading i915 perf counters
# as a normal user. The rc6-residency method below needs no privileges and
# stays the right approach: rc6_residency_ms is cumulative time in the GPU's
# idle power state, so the delta over a window as a fraction of that window
# is idle% — 100 minus that is busy%.
set -uo pipefail

INTERVAL=${1:-5}

gpu_card=/sys/class/drm/card1
gpu_rc6=$gpu_card/gt/gt0/rc6_residency_ms
rapl=/sys/class/powercap/intel-rapl:0/energy_uj

# --- static identity, read once -------------------------------------------
cpu_name=$(grep -m1 '^model name' /proc/cpuinfo | cut -d: -f2- | sed 's/^ *//;s/ *$//')
cpu_cores=$(nproc 2>/dev/null || echo 0)
gpu_name=$(lspci -mm 2>/dev/null | awk -F'"' '/VGA compatible controller|3D controller/ { print $6; exit }')
gpu_vendor=$(lspci -mm 2>/dev/null | awk -F'"' '/VGA compatible controller|3D controller/ { print $4; exit }')
: "${cpu_name:=unknown}" "${gpu_name:=unknown}" "${gpu_vendor:=unknown}"

# RAM type/speed/channel count from SMBIOS, via passwordless sudo dmidecode
# (this machine's sudoers grants NOPASSWD: ALL — see configs/sudoers). Read
# once at startup like cpu_name/gpu_name: physically installed memory does
# not change while the shell is running. Populated devices only (empty
# Size means an unpopulated slot) so an asymmetric/single-DIMM machine
# reports correctly instead of a bogus zero-size channel.
mem_type=""
mem_speed_mts=0
mem_channels=0
if command -v dmidecode >/dev/null 2>&1; then
    dmi=$(sudo -n dmidecode -t memory 2>/dev/null || true)
    if [[ -n "$dmi" ]]; then
        mem_type=$(awk -F': ' '/^\s*Type:/ && $2 !~ /Unknown/ {print $2; exit}' <<<"$dmi")
        mem_speed_mts=$(awk -F': ' '/^\s*Configured Memory Speed:/ && $2 !~ /Unknown/ {print $2; exit}' <<<"$dmi" | grep -oE '^[0-9]+')
        mem_channels=$(awk '/^\s*Size:/ && $0 !~ /No Module Installed/ {n++} END {print n+0}' <<<"$dmi")
    fi
fi
: "${mem_type:=}" "${mem_speed_mts:=0}" "${mem_channels:=0}"

case "$gpu_vendor" in
*Intel*) gpu_vendor=intel ;;
*AMD*|*ATI*|*Advanced\ Micro*) gpu_vendor=amd ;;
*NVIDIA*) gpu_vendor=nvidia ;;
*) gpu_vendor=unknown ;;
esac

# Root-only by file permission (mode 0400). configs/udev/99-powercap.rules
# grants group-read; without it this stays null and the panel says the
# reading is unavailable rather than printing 0 W.
power_ok=0
[[ -r "$rapl" ]] && power_ok=1

mem_total_kb=$(awk '/^MemTotal:/{print $2}' /proc/meminfo)

# --- sampling loop --------------------------------------------------------
read -r _ pu pn ps pi _ < /proc/stat
prev_rc6=$(cat "$gpu_rc6" 2>/dev/null || echo 0)
prev_t_ms=$(date +%s%3N)
prev_energy=0
((power_ok)) && prev_energy=$(cat "$rapl" 2>/dev/null || echo 0)

# First sample uses a SHORT window so the bar has real numbers within a
# fraction of a second of the shell starting. Sleeping the full interval
# first meant every restart showed "0% 0MHz  0.0G  0deg" for five seconds —
# the one-shot version this replaced sampled immediately, so that was a
# regression when it became a streaming helper.
delay=0.3
while :; do
    sleep "$delay"
    delay=$INTERVAL

    read -r _ cu cn cs ci _ < /proc/stat
    rc6=$(cat "$gpu_rc6" 2>/dev/null || echo 0)
    t_ms=$(date +%s%3N)

    total_prev=$((pu + pn + ps + pi))
    total_now=$((cu + cn + cs + ci))
    cpu_pct=$(awk -v t1="$total_prev" -v t2="$total_now" -v i1="$pi" -v i2="$ci" \
        'BEGIN { dt = t2 - t1; di = i2 - i1; printf "%.0f", (dt > 0 ? (dt - di) * 100 / dt : 0) }')

    gpu_pct=$(awk -v r1="$prev_rc6" -v r2="$rc6" -v t1="$prev_t_ms" -v t2="$t_ms" \
        'BEGIN {
            dt = t2 - t1; dr = r2 - r1
            pct = dt > 0 ? 100 - (dr * 100 / dt) : 0
            if (pct < 0) pct = 0
            if (pct > 100) pct = 100
            printf "%.0f", pct
        }')

    # Package power from the RAPL energy counter. It is a wrapping
    # microjoule counter, so a negative delta means it wrapped: skip that
    # sample rather than reporting a nonsense spike.
    power_w=null
    if ((power_ok)); then
        energy=$(cat "$rapl" 2>/dev/null || echo 0)
        power_w=$(awk -v e1="$prev_energy" -v e2="$energy" -v t1="$prev_t_ms" -v t2="$t_ms" \
            'BEGIN {
                de = e2 - e1; dt = (t2 - t1) / 1000
                if (de < 0 || dt <= 0) { print "null" } else { printf "%.1f", de / 1000000 / dt }
            }')
        prev_energy=$energy
    fi

    gpu_freq=$(cat "$gpu_card/gt_act_freq_mhz" 2>/dev/null || echo 0)
    freq_mhz=$(($(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq 2>/dev/null || echo 0) / 1000))
    temp=$(sensors -j 2>/dev/null | jq -r '.["coretemp-isa-0000"]["Package id 0"].temp1_input // empty' | cut -d. -f1)
    temp=${temp:-0}
    mem_avail_kb=$(awk '/^MemAvailable:/{print $2}' /proc/meminfo)

    jq -nc \
        --arg cpuName "$cpu_name" --argjson cpuCores "${cpu_cores:-0}" \
        --arg gpuName "$gpu_name" --arg gpuVendor "$gpu_vendor" \
        --argjson cpu "${cpu_pct:-0}" --argjson freqMhz "${freq_mhz:-0}" \
        --argjson tempC "${temp:-0}" \
        --argjson memUsedGb "$(awk -v t="$mem_total_kb" -v a="$mem_avail_kb" 'BEGIN { printf "%.2f", (t - a) / 1048576 }')" \
        --argjson memTotalGb "$(awk -v t="$mem_total_kb" 'BEGIN { printf "%.2f", t / 1048576 }')" \
        --arg memType "$mem_type" --argjson memSpeedMts "${mem_speed_mts:-0}" --argjson memChannels "${mem_channels:-0}" \
        --argjson gpuPct "${gpu_pct:-0}" --argjson gpuFreqMhz "${gpu_freq:-0}" \
        --argjson powerW "${power_w:-null}" \
        '{cpuName:$cpuName, cpuCores:$cpuCores, gpuName:$gpuName, gpuVendor:$gpuVendor,
          cpu:$cpu, freqMhz:$freqMhz, tempC:$tempC,
          memUsedGb:$memUsedGb, memTotalGb:$memTotalGb,
          memType:$memType, memSpeedMts:$memSpeedMts, memChannels:$memChannels,
          gpuPct:$gpuPct, gpuFreqMhz:$gpuFreqMhz,
          powerW:$powerW,
          vramUsedMb:null, vramTotalMb:null}'

    pu=$cu; pn=$cn; ps=$cs; pi=$ci
    prev_rc6=$rc6; prev_t_ms=$t_ms
done

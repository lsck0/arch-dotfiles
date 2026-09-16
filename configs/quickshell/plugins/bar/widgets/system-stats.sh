#!/usr/bin/env bash
# Streams one JSON line per sample: CPU, memory, GPU (busy/clock/VRAM/power)
# and package temperature/power.
#
# LONG-LIVED, not one-shot. This used to be respawned by System.qml every 5
# seconds, which meant a fresh bash plus ~8 forks per sample forever. It now
# runs once and prints a line per interval, read with SplitParser — the same
# shape as the cava and `nmcli monitor` readers.
#
# HARDWARE-ADAPTIVE. This repo runs on more than one machine (see
# hyprland_monitors.lua's "notebook"/"desktop" split), and CPU/GPU vendor and
# sensor layout differ between them:
#
#   * Temperature: probed from `sensors -j` rather than a hardcoded chip/label
#     pair. Package temp lives under different labels per platform —
#     "Package id 0" (Intel coretemp), "Tctl"/"Tdie" (AMD k10temp) — so every
#     known label is tried in priority order and the first hit wins. A
#     machine with none of them (rare, but possible in a VM) reports 0 rather
#     than erroring.
#   * GPU: identified by vendor from lspci, then read through whichever sysfs
#     interface that vendor exposes on /sys/class/drm/card*:
#       - amdgpu: gpu_busy_percent, pp_dpm_sclk's "*" entry, and
#         mem_info_vram_{used,total} for VRAM — all present on every amdgpu
#         card, no privilege needed.
#       - i915 (Intel iGPU): no VRAM concept and no gpu_busy_percent; busy%
#         is derived from rc6_residency_ms idle-time delta (100 - idle%),
#         same method the previous single-platform version used.
#     Whichever wins is picked from the FIRST GPU lspci reports as a VGA/3D
#     controller — this only handles one GPU card; a desktop with a
#     discrete card AND an iGPU shows the discrete one, which is what
#     `hl.env` extensions in this repo already assume is the "real" GPU.
#   * GPU power: amdgpu publishes its own PPT reading via hwmon
#     (power1_average newer kernels, power1_input on some); i915 has none, so
#     the RAPL psys/pkg energy counter is used there instead, unchanged from
#     before.
#
# WHAT SOME HARDWARE CANNOT REPORT. Real hardware facts, not gaps — the
# widget shows the field as unavailable (null) rather than a plausible zero:
#
#   * CPU/GPU voltage — no consistent cross-vendor hwmon voltage input;
#     package power in watts is reported instead.
#   * VRAM on an iGPU — i915 has no VRAM concept and no sysfs equivalent of
#     amdgpu's mem_info_vram_used. Emitted as null and gated on `gpuVendor`
#     in System.qml.
set -uo pipefail

INTERVAL=${1:-5}

# --- static identity, read once -------------------------------------------
cpu_name=$(grep -m1 '^model name' /proc/cpuinfo | cut -d: -f2- | sed 's/^ *//;s/ *$//')
cpu_cores=$(nproc 2>/dev/null || echo 0)
gpu_name=$(lspci -mm 2>/dev/null | awk -F'"' '/VGA compatible controller|3D controller/ { print $6; exit }')
gpu_vendor_raw=$(lspci -mm 2>/dev/null | awk -F'"' '/VGA compatible controller|3D controller/ { print $4; exit }')
: "${cpu_name:=unknown}" "${gpu_name:=unknown}" "${gpu_vendor_raw:=unknown}"

case "$gpu_vendor_raw" in
*Intel*) gpu_vendor=intel ;;
*AMD*|*ATI*|*Advanced\ Micro*) gpu_vendor=amd ;;
*NVIDIA*) gpu_vendor=nvidia ;;
*) gpu_vendor=unknown ;;
esac

# Locate this GPU's /sys/class/drm/cardN — matched by PCI vendor:device id
# (lspci -n) against each card's device/{vendor,device} rather than by
# name/position, since card numbering is not guaranteed to match discovery
# order across reboots.
gpu_card=""
gpu_pci=$(lspci -Dnmm 2>/dev/null | awk '/ 0300: | 0302: /{ print $1; exit }')
if [[ -n "$gpu_pci" ]]; then
    for c in /sys/class/drm/card[0-9]*; do
        [[ -e "$c/device" ]] || continue
        dev_path=$(readlink -f "$c/device")
        [[ "$dev_path" == *"$gpu_pci" ]] && { gpu_card="$c"; break; }
    done
fi
[[ -z "$gpu_card" ]] && gpu_card=/sys/class/drm/card1  # last-resort guess

# amdgpu's hwmon dir, for power1_average/power1_input.
amdgpu_hwmon=""
if [[ "$gpu_vendor" == amd ]]; then
    for h in "$gpu_card"/device/hwmon/hwmon*; do
        [[ -f "$h/name" ]] || continue
        [[ "$(cat "$h/name" 2>/dev/null)" == amdgpu ]] && { amdgpu_hwmon="$h"; break; }
    done
fi

gpu_rc6=$gpu_card/gt/gt0/rc6_residency_ms  # i915 only
rapl=/sys/class/powercap/intel-rapl:0/energy_uj  # i915 platforms only

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

# Package temperature: try every known "this is the CPU package" sensors
# label, across chips, in priority order. `sensors -j` nests chip -> feature
# -> {tempN_input: ...}, so this walks every chip's features once per sample
# looking for the first matching label; cheap (one process, one jq pass) and
# tolerant of a machine exposing more than one candidate (e.g. a temp1 on an
# unrelated chip) by preferring the known package-temp labels first.
read_temp() {
    sensors -j 2>/dev/null | jq -r '
        def pick(k): [.[] | to_entries[] | select(.key == k) | (.value.temp1_input // .value.temp2_input // .value.temp3_input)] | first;
        (pick("Package id 0") // pick("Tctl") // pick("Tdie") // pick("CPU Temperature") // pick("temp1")) // empty
    ' | cut -d. -f1
}

# amdgpu power: power1_average (newer amdgpu) then power1_input (older).
read_amdgpu_power() {
    [[ -n "$amdgpu_hwmon" ]] || { echo null; return; }
    local raw=""
    [[ -f "$amdgpu_hwmon/power1_average" ]] && raw=$(cat "$amdgpu_hwmon/power1_average" 2>/dev/null)
    [[ -z "$raw" && -f "$amdgpu_hwmon/power1_input" ]] && raw=$(cat "$amdgpu_hwmon/power1_input" 2>/dev/null)
    if [[ -n "$raw" && "$raw" =~ ^[0-9]+$ ]]; then
        awk -v uw="$raw" 'BEGIN { printf "%.1f", uw / 1000000 }'
    else
        echo null
    fi
}

power_ok=0
[[ "$gpu_vendor" != amd && -r "$rapl" ]] && power_ok=1

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
    t_ms=$(date +%s%3N)

    total_prev=$((pu + pn + ps + pi))
    total_now=$((cu + cn + cs + ci))
    cpu_pct=$(awk -v t1="$total_prev" -v t2="$total_now" -v i1="$pi" -v i2="$ci" \
        'BEGIN { dt = t2 - t1; di = i2 - i1; printf "%.0f", (dt > 0 ? (dt - di) * 100 / dt : 0) }')

    power_w=null
    vram_used_mb=null
    vram_total_mb=null
    gpu_freq=0

    if [[ "$gpu_vendor" == amd ]]; then
        gpu_pct=$(cat "$gpu_card/device/gpu_busy_percent" 2>/dev/null || echo 0)
        gpu_freq=$(awk -F'[ *Mhz]+' '/\*/{print $2; exit}' "$gpu_card/device/pp_dpm_sclk" 2>/dev/null || echo 0)
        vram_used_b=$(cat "$gpu_card/device/mem_info_vram_used" 2>/dev/null || echo "")
        vram_total_b=$(cat "$gpu_card/device/mem_info_vram_total" 2>/dev/null || echo "")
        if [[ -n "$vram_used_b" && -n "$vram_total_b" ]]; then
            vram_used_mb=$(awk -v b="$vram_used_b" 'BEGIN { printf "%.0f", b / 1048576 }')
            vram_total_mb=$(awk -v b="$vram_total_b" 'BEGIN { printf "%.0f", b / 1048576 }')
        fi
        power_w=$(read_amdgpu_power)
        rc6=$prev_rc6  # unused on this path
    else
        rc6=$(cat "$gpu_rc6" 2>/dev/null || echo 0)
        gpu_pct=$(awk -v r1="$prev_rc6" -v r2="$rc6" -v t1="$prev_t_ms" -v t2="$t_ms" \
            'BEGIN {
                dt = t2 - t1; dr = r2 - r1
                pct = dt > 0 ? 100 - (dr * 100 / dt) : 0
                if (pct < 0) pct = 0
                if (pct > 100) pct = 100
                printf "%.0f", pct
            }')
        gpu_freq=$(cat "$gpu_card/gt_act_freq_mhz" 2>/dev/null || echo 0)

        # Package power from the RAPL energy counter. It is a wrapping
        # microjoule counter, so a negative delta means it wrapped: skip
        # that sample rather than reporting a nonsense spike.
        if ((power_ok)); then
            energy=$(cat "$rapl" 2>/dev/null || echo 0)
            power_w=$(awk -v e1="$prev_energy" -v e2="$energy" -v t1="$prev_t_ms" -v t2="$t_ms" \
                'BEGIN {
                    de = e2 - e1; dt = (t2 - t1) / 1000
                    if (de < 0 || dt <= 0) { print "null" } else { printf "%.1f", de / 1000000 / dt }
                }')
            prev_energy=$energy
        fi
    fi

    freq_mhz=$(($(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq 2>/dev/null || echo 0) / 1000))
    temp=$(read_temp)
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
        --argjson vramUsedMb "${vram_used_mb:-null}" --argjson vramTotalMb "${vram_total_mb:-null}" \
        '{cpuName:$cpuName, cpuCores:$cpuCores, gpuName:$gpuName, gpuVendor:$gpuVendor,
          cpu:$cpu, freqMhz:$freqMhz, tempC:$tempC,
          memUsedGb:$memUsedGb, memTotalGb:$memTotalGb,
          memType:$memType, memSpeedMts:$memSpeedMts, memChannels:$memChannels,
          gpuPct:$gpuPct, gpuFreqMhz:$gpuFreqMhz,
          powerW:$powerW,
          vramUsedMb:$vramUsedMb, vramTotalMb:$vramTotalMb}'

    pu=$cu; pn=$cn; ps=$cs; pi=$ci
    prev_rc6=$rc6; prev_t_ms=$t_ms
done

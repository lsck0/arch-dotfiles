#!/usr/bin/env bash
# streams one json line of system stats per sample
set -uo pipefail

INTERVAL=${1:-10}

cpu_name=$(grep -m1 '^model name' /proc/cpuinfo | cut -d: -f2- | sed 's/^ *//;s/ *$//')
cpu_cores=$(nproc 2>/dev/null || echo 0)
IFS=$'\t' read -r gpu_vendor_raw gpu_name < <(lspci -mm 2>/dev/null \
    | awk -F'"' '/VGA compatible controller|3D controller/ { print $4 "\t" $6; exit }')
: "${cpu_name:=unknown}" "${gpu_name:=unknown}" "${gpu_vendor_raw:=unknown}"

case "$gpu_vendor_raw" in
*Intel*) gpu_vendor=intel ;;
*AMD*|*ATI*|*Advanced\ Micro*) gpu_vendor=amd ;;
*NVIDIA*) gpu_vendor=nvidia ;;
*) gpu_vendor=unknown ;;
esac

# match the drm card by pci address, card numbering is not stable
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

amdgpu_hwmon=""
if [[ "$gpu_vendor" == amd ]]; then
    for h in "$gpu_card"/device/hwmon/hwmon*; do
        [[ -f "$h/name" ]] || continue
        [[ "$(cat "$h/name" 2>/dev/null)" == amdgpu ]] && { amdgpu_hwmon="$h"; break; }
    done
fi

gpu_rc6=$gpu_card/gt/gt0/rc6_residency_ms  # i915 only
# intel-rapl is also the name on amd zen
rapl=/sys/class/powercap/intel-rapl:0/energy_uj
rapl_max=$(cat /sys/class/powercap/intel-rapl:0/max_energy_range_uj 2>/dev/null || echo 0)
# on tmpfs so a shell restart does not reset it
energy_file=${XDG_RUNTIME_DIR:-/tmp}/quickshell-energy-wh
# unmetered ram, board, drives and fans
OVERHEAD_W=40
PSU_EFFICIENCY=0.9

# resolve the hwmon path once instead of spawning sensors every tick
cpu_temp_path=""
for h in /sys/class/hwmon/hwmon*; do
    [[ -f "$h/name" ]] || continue
    case "$(cat "$h/name" 2>/dev/null)" in
    k10temp|coretemp|zenpower) ;;
    *) continue ;;
    esac
    # prefer the package label, else temp1_input
    for lbl in "$h"/temp*_label; do
        [[ -f "$lbl" ]] || continue
        case "$(cat "$lbl" 2>/dev/null)" in
        Tctl|Tdie|Package*|"CPU Temperature")
            cand="${lbl%_label}_input"
            [[ -r "$cand" ]] && { cpu_temp_path="$cand"; break; }
            ;;
        esac
    done
    [[ -z "$cpu_temp_path" && -r "$h/temp1_input" ]] && cpu_temp_path="$h/temp1_input"
    [[ -n "$cpu_temp_path" ]] && break
done

# dmidecode needs passwordless sudo
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

# static fields once, jq escapes the names
static_json=$(jq -nc --arg cpuName "$cpu_name" --argjson cpuCores "${cpu_cores:-0}" --arg gpuName "$gpu_name" \
    --arg gpuVendor "$gpu_vendor" --arg memType "$mem_type" --argjson memSpeedMts "${mem_speed_mts:-0}" \
    --argjson memChannels "${mem_channels:-0}" \
    '{cpuName:$cpuName, cpuCores:$cpuCores, gpuName:$gpuName, gpuVendor:$gpuVendor, memType:$memType,
      memSpeedMts:$memSpeedMts, memChannels:$memChannels}')

# REPLY = first line of a sysfs/proc file, empty when unreadable; builtins only, a tick forks nothing but awk
file_read() {
    REPLY=
    [[ -r "$1" ]] && read -r REPLY <"$1"
    return 0
}

# power1_average on newer amdgpu, power1_input on older
amdgpu_power_path=""
for f in "$amdgpu_hwmon"/power1_average "$amdgpu_hwmon"/power1_input; do
    [[ -n "$amdgpu_hwmon" && -r "$f" ]] && { amdgpu_power_path=$f; break; }
done

mem_total_kb=$(awk '/^MemTotal:/{print $2}' /proc/meminfo)
# sleep without forking: read on a pipe nobody writes times out
exec {sleep_fd}<> <(:)

prev_stat=$(head -n1 /proc/stat)
file_read "$gpu_rc6"; prev_rc6=${REPLY:-0}
file_read "$rapl"; prev_energy=${REPLY:-0}
prev_t_us=${EPOCHREALTIME/./}
temp=0

# short first window so the bar fills in fast
delay=0.3
while :; do
    read -rt "$delay" -u "$sleep_fd" _ || true
    delay=$INTERVAL

    IFS= read -r stat </proc/stat
    t_us=${EPOCHREALTIME/./}
    gpu_busy=""; gpu_freq=0; vram_used_b=""; vram_total_b=""; gpu_power_uw=""; rc6=$prev_rc6
    if [[ "$gpu_vendor" == amd ]]; then
        file_read "$gpu_card/device/gpu_busy_percent"; gpu_busy=$REPLY
        # the active level is starred: "1: 700Mhz *"
        while read -r _ mhz star; do [[ "$star" == '*' ]] && { gpu_freq=${mhz%Mhz}; break; }; done \
            <"$gpu_card/device/pp_dpm_sclk" 2>/dev/null
        file_read "$gpu_card/device/mem_info_vram_used"; vram_used_b=$REPLY
        file_read "$gpu_card/device/mem_info_vram_total"; vram_total_b=$REPLY
        file_read "$amdgpu_power_path"; gpu_power_uw=$REPLY
    else
        file_read "$gpu_rc6"; rc6=${REPLY:-0}
        file_read "$gpu_card/gt_act_freq_mhz"; gpu_freq=${REPLY:-0}
    fi
    file_read "$rapl"; energy=$REPLY
    file_read /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq; freq_khz=${REPLY:-0}
    file_read "$cpu_temp_path"; [[ "$REPLY" =~ ^-?[0-9]+$ ]] && temp=$((REPLY / 1000))
    while read -r key value _; do [[ "$key" == MemAvailable: ]] && break; done </proc/meminfo
    file_read "$energy_file"; energy_wh=${REPLY:-0}

    awk -v static="$static_json" -v stat0="$prev_stat" -v stat1="$stat" -v dt_us="$((t_us - prev_t_us))" \
        -v vendor="$gpu_vendor" -v busy="$gpu_busy" -v rc6_0="$prev_rc6" -v rc6_1="$rc6" -v gpu_freq="${gpu_freq:-0}" \
        -v vram_used="$vram_used_b" -v vram_total="$vram_total_b" -v gpu_uw="$gpu_power_uw" \
        -v e0="$prev_energy" -v e1="$energy" -v emax="$rapl_max" -v freq_khz="$freq_khz" -v temp="$temp" \
        -v mem_total="$mem_total_kb" -v mem_avail="$value" -v energy_wh="$energy_wh" -v energy_file="$energy_file" \
        -v overhead="$OVERHEAD_W" -v eff="$PSU_EFFICIENCY" '
        function num_or_null(v, fmt) { return v == "" ? "null" : sprintf(fmt, v) }
        BEGIN {
            split(stat0, a, " "); split(stat1, b, " ")
            total = (b[2] + b[3] + b[4] + b[5]) - (a[2] + a[3] + a[4] + a[5]); idle = b[5] - a[5]
            cpu = total > 0 ? (total - idle) * 100 / total : 0
            dt_ms = dt_us / 1000
            if (vendor == "amd") gpu = busy + 0
            else { gpu = dt_ms > 0 ? 100 - (rc6_1 - rc6_0) * 100 / dt_ms : 0; gpu = gpu < 0 ? 0 : (gpu > 100 ? 100 : gpu) }
            gpu_w = gpu_uw ~ /^[0-9]+$/ ? gpu_uw / 1000000 : ""
            cpu_w = ""
            if (e1 != "") { de = e1 - e0; if (de < 0 && emax > 0) de += emax; if (de >= 0 && dt_ms > 0) cpu_w = de / 1000 / dt_ms }
            power_w = ""
            if (cpu_w != "" || gpu_w != "") {
                power_w = (cpu_w + gpu_w + overhead) / eff
                energy_wh += power_w * dt_ms / 3600000
                printf "%.4f\n", energy_wh > energy_file
            }
            printf "%s,\"cpu\":%.0f,\"freqMhz\":%d,\"tempC\":%d,\"memUsedGb\":%.2f,\"memTotalGb\":%.2f,\"gpuPct\":%.0f,\"gpuFreqMhz\":%d,",
                substr(static, 1, length(static) - 1), cpu, freq_khz / 1000, temp,
                (mem_total - mem_avail) / 1048576, mem_total / 1048576, gpu, gpu_freq
            printf "\"powerW\":%s,\"cpuPowerW\":%s,\"gpuPowerW\":%s,\"energyKwh\":%.4f,\"vramUsedMb\":%s,\"vramTotalMb\":%s}\n",
                num_or_null(power_w, "%.1f"), num_or_null(cpu_w, "%.1f"), num_or_null(gpu_w, "%.1f"), energy_wh / 1000,
                num_or_null(vram_used == "" ? "" : vram_used / 1048576, "%.0f"),
                num_or_null(vram_total == "" ? "" : vram_total / 1048576, "%.0f")
        }'

    prev_stat=$stat; prev_rc6=$rc6; prev_t_us=$t_us
    [[ -n "$energy" ]] && prev_energy=$energy
done

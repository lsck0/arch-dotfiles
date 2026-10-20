#!/usr/bin/env -S nu --no-config-file

const OVERHEAD_W = 40
const PSU_EFFICIENCY = 0.9
const FIRST_SAMPLE = 300ms
# intel-rapl is also the name on amd zen
const RAPL = "/sys/class/powercap/intel-rapl:0"
const DMI_DEVICE = "/devices/virtual/dmi/id"
const CPU_TEMP_DRIVERS = [k10temp coretemp zenpower]
const CPU_TEMP_LABEL = '^(Tctl|Tdie|Package.*|CPU Temperature)$'
const CPU_FREQ = "/sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq"
const GPU_CLASSES = '^\S+ (0300|0302): '
const TOP_COUNT = 2
# utime and stime after the comm field of /proc/<pid>/stat
const PROC_STAT = '(?m)^(?<pid>\d+) \((?<name>.*)\) \S+(?: \S+){10} (?<utime>\d+) (?<stime>\d+) '
const GPU_TEMP_LABEL = "edge"
const MS_PER_HOUR = 3_600_000
const UW_PER_W = 1_000_000
const KIB_PER_GIB = 1048576
const BYTES_PER_MIB = 1048576

# unreadable reads as missing: intel-rapl energy_uj is root-only, and a throw here respawns the script forever
def line-read [path?: string]: nothing -> string {
    if $path == null { return "" }
    try { open --raw $path | lines | get 0? | default "" } catch { "" }
}

def int-read [path?: string]: nothing -> int {
    line-read $path | default -e "0" | into int
}

def number-or-null [value: string, divisor: number]: nothing -> any {
    if $value =~ '^[0-9]+$' { ($value | into int) / $divisor }
}

def round-or-null [precision: int]: any -> any {
    if $in != null { math round -p $precision }
}

def stat-read []: nothing -> list<int> {
    open --raw /proc/stat | lines | first | split row -r '\s+' | slice 1..4 | into int
}

def top-by-name []: table -> list {
    group-by name | items {|name, rows| {name: $name, pct: ($rows.pct | math sum)} }
        | sort-by pct -r | first $TOP_COUNT | update pct { math round -p 1 }
}

def proc-ticks []: nothing -> table {
    let self = $nu.pid | into string
    glob /proc/[0-9]*/stat | each {|f| try { open --raw $f } } | str join "\n" | parse -r $PROC_STAT
        | where pid != $self
        | each {|p| {pid: $p.pid, name: $p.name, ticks: (($p.utime | into int) + ($p.stime | into int))} }
}

# ps %cpu is the lifetime average, this is the share of one core since the last sample, like top
def top-cpu [now: table, before: table, dt_ms: number, tck: int]: nothing -> list {
    if $dt_ms <= 0 { return [] }
    $now | join --left $before pid | each {|p|
        let ticks = [($p.ticks - ($p.ticks_? | default 0)) 0] | math max
        {name: $p.name, pct: ($ticks * 100_000 / $tck / $dt_ms)}
    } | where pct > 0 | top-by-name
}

def top-mem []: nothing -> list {
    ^ps -eo %mem,comm --no-headers | lines | parse -r '^\s*(?<pct>\S+)\s+(?<name>.*)$'
        | each {|p| {name: ($p.name | str trim), pct: ($p.pct | into float)} } | top-by-name
}

def hardware-detect []: nothing -> record {
    let gpu = ^lspci -mm | lines | where $it =~ 'VGA compatible controller|3D controller' | get 0? | default "" | split row '"'
    let gpu_vendor_raw = $gpu | get 3? | default unknown
    # match the drm card by pci address, card numbering is not stable
    let gpu_pci = ^lspci -Dn | lines | where $it =~ $GPU_CLASSES | get 0? | default "" | split row " " | first
    let gpu_card = glob /sys/class/drm/card[0-9]* | sort | where {|c| $gpu_pci != "" and ($"($c)/device" | path exists) and ($"($c)/device" | path expand | str ends-with $gpu_pci) } | get 0? | default /sys/class/drm/card1
    let gpu_vendor = match $gpu_vendor_raw {
        $v if $v =~ Intel => "intel"
        $v if $v =~ 'AMD|ATI|Advanced Micro' => "amd"
        $v if $v =~ NVIDIA => "nvidia"
        _ => "unknown"
    }
    let amdgpu_hwmon = if $gpu_vendor == amd { glob $"($gpu_card)/device/hwmon/hwmon*" | sort | where { line-read $"($in)/name" | $in == amdgpu } | get 0? }
    let gpu_temp = if $amdgpu_hwmon == null { null } else {
        glob $"($amdgpu_hwmon)/temp*_label" | sort | where { line-read $in | $in == $GPU_TEMP_LABEL }
            | each { str replace -r '_label$' '_input' } | where { path exists } | get 0?
    }
    let cpu_temp = glob /sys/class/hwmon/hwmon* | sort | where { line-read $"($in)/name" | $in in $CPU_TEMP_DRIVERS } | each {|h|
        glob $"($h)/temp*_label" | sort | where { line-read $in | $in =~ $CPU_TEMP_LABEL } | each { str replace -r '_label$' '_input' } | append $"($h)/temp1_input"
    } | flatten | where { path exists } | get 0?

    # udev's dmi_memory_id import (70-memory.rules) is readable without root, unlike dmidecode
    let dmi = ^udevadm info --query=property $"--path=($DMI_DEVICE)" | complete | get stdout | lines | parse 'MEMORY_DEVICE_{slot}_{key}={value}'
    let field = {|key| $dmi | where key == $key }
    let populated = do $field SIZE | where ($it.value | into int) > 0 | get slot
    let banks = do $field BANK_LOCATOR | where slot in $populated
    {
        static: {
            cpuName: (open /proc/cpuinfo | lines | where $it starts-with "model name" | get 0? | default "" | str replace -r '^[^:]*:' '' | str trim | default -e unknown)
            cpuCores: (^nproc | into int)
            gpuName: ($gpu | get 5? | default unknown)
            gpuVendor: $gpu_vendor
            memType: (do $field TYPE | where value != Unknown | get value.0? | default "")
            memSpeedMts: (do $field CONFIGURED_SPEED_MTS | where ($it.value | into int) > 0 | get value.0? | default 0 | into int)
            memChannels: (if ($banks | length) == ($populated | length) { $banks | get value | uniq | length } else { $populated | length })
        }
        gpu_card: $gpu_card
        gpu_power: (if $amdgpu_hwmon == null { null } else {
            [power1_average power1_input] | each { [$amdgpu_hwmon $in] | path join } | where { $in | path exists } | get 0?
        })
        cpu_temp: $cpu_temp
        gpu_temp: $gpu_temp
        rapl_max: (int-read $"($RAPL)/max_energy_range_uj")
        mem_total_kb: (open /proc/meminfo | lines | first | split row -r '\s+' | get 1 | into int)
    }
}

def main [interval_s: number = 10] {
    let hw = hardware-detect
    let amd = $hw.static.gpuVendor == amd
    let device = $"($hw.gpu_card)/device"
    let rc6_path = $"($hw.gpu_card)/gt/gt0/rc6_residency_ms"
    # without rc6 the busy share would read 100%: null, and the bar hides it
    let has_rc6 = (line-read $rc6_path) != ""
    let energy_file = [($env.XDG_RUNTIME_DIR? | default /tmp) quickshell-energy-wh] | path join

    let tck = ^getconf CLK_TCK | into int
    mut prev = {
        stat: (stat-read), rc6: (int-read $rc6_path), energy: (line-read $"($RAPL)/energy_uj"), procs: (proc-ticks)
        time: (date now)
    }
    mut temp_c = 0
    mut delay = $FIRST_SAMPLE
    loop {
        sleep $delay
        $delay = $interval_s * 1sec

        let stat = stat-read
        let procs = proc-ticks
        let time = date now
        let dt_ms = ($time - $prev.time) / 1ms
        let rc6 = if $amd { $prev.rc6 } else { int-read $rc6_path }
        let energy = line-read $"($RAPL)/energy_uj"
        let temp_raw = line-read $hw.cpu_temp
        if $temp_raw =~ '^-?[0-9]+$' { $temp_c = ($temp_raw | into int) // 1000 }

        let total = ($stat | math sum) - ($prev.stat | math sum)
        let idle = $stat.3 - $prev.stat.3
        let gpu_pct = if $amd {
            number-or-null (line-read $"($device)/gpu_busy_percent") 1
        } else if $has_rc6 and $dt_ms > 0 {
            100 - ($rc6 - $prev.rc6) * 100 / $dt_ms | [$in 0] | math max | [$in 100] | math min
        }
        let gpu_freq = if $amd {
            # the active level is starred: "1: 700Mhz *"
            try { open --raw $"($device)/pp_dpm_sclk" } catch { "" } | parse -r '(?<mhz>\d+)Mhz \*' | get mhz.0? | default 0 | into int
        } else { int-read $"($hw.gpu_card)/gt_act_freq_mhz" }
        let gpu_w = if $amd { number-or-null (line-read $hw.gpu_power) $UW_PER_W }
        let gpu_temp_c = number-or-null (line-read $hw.gpu_temp) 1000 | if $in != null { math round }
        let cpu_w = if $energy != "" and $prev.energy != "" and $dt_ms > 0 {
            let delta = ($energy | into int) - ($prev.energy | into int)
            let wrapped = if $delta < 0 and $hw.rapl_max > 0 { $delta + $hw.rapl_max } else { $delta }
            if $wrapped >= 0 { $wrapped / 1000 / $dt_ms }
        }
        let power_w = if $cpu_w != null or $gpu_w != null { (($cpu_w | default 0) + ($gpu_w | default 0) + $OVERHEAD_W) / $PSU_EFFICIENCY }
        let energy_wh = (line-read $energy_file | default -e "0" | into float) + ($power_w | default 0) * $dt_ms / $MS_PER_HOUR
        if $power_w != null { $"($energy_wh | math round -p 4)\n" | save -f $energy_file }
        def vram-mb [kind: string]: nothing -> any {
            if $amd { number-or-null (line-read $"($device)/mem_info_vram_($kind)") $BYTES_PER_MIB | if $in != null { math round } }
        }
        let vram_used_mb = vram-mb used
        let vram_total_mb = vram-mb total
        let mem_available_kb = open /proc/meminfo | lines | where $it starts-with MemAvailable: | first | split row -r '\s+' | get 1 | into int

        $hw.static | merge {
            cpu: (if $total > 0 { ($total - $idle) * 100 / $total } else { 0 } | math round)
            freqMhz: ((int-read $CPU_FREQ) // 1000)
            tempC: $temp_c
            memUsedGb: (($hw.mem_total_kb - $mem_available_kb) / $KIB_PER_GIB | math round -p 2)
            memTotalGb: ($hw.mem_total_kb / $KIB_PER_GIB | math round -p 2)
            gpuPct: ($gpu_pct | if $in != null { math round })
            gpuFreqMhz: $gpu_freq
            gpuTempC: $gpu_temp_c
            powerW: ($power_w | round-or-null 1)
            cpuPowerW: ($cpu_w | round-or-null 1)
            gpuPowerW: ($gpu_w | round-or-null 1)
            energyKwh: ($energy_wh / 1000 | math round -p 4)
            vramUsedMb: $vram_used_mb
            vramTotalMb: $vram_total_mb
            top: {cpu: (top-cpu $procs $prev.procs $dt_ms $tck), mem: (top-mem)}
        } | to json -r | print

        $prev = {
            stat: $stat, rc6: $rc6, energy: (if $energy != "" { $energy } else { $prev.energy }), procs: $procs
            time: $time
        }
    }
}

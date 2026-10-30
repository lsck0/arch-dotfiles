#!/usr/bin/env -S nu --no-config-file
# GiB, the base the bar's system panel uses under the same G suffix
const KIB_PER_GIB = 1048576

def main [] {
    let load = open /proc/loadavg | split row " " | first | into float
    let load_pct = $load * 100 / (sys cpu | length) | math round
    let meminfo = open --raw /proc/meminfo | parse --regex '(?m)^(?<key>MemTotal|MemAvailable):\s+(?<kib>\d+) kB' | transpose -r -d
    let total_gib = ($meminfo.MemTotal | into int) / $KIB_PER_GIB
    let used_gib = (($meminfo.MemTotal | into int) - ($meminfo.MemAvailable | into int)) / $KIB_PER_GIB
    let mem = $"($used_gib | into string -d 1)/($total_gib | math round)G"
    let up = ^uptime -p | str replace --regex '^up ' "" | str replace --regex ' hours?' "h" | str replace --regex ' minutes?' "m"
        | str replace --all "," ""
    print $"(^uname -r | str trim)   load ($load_pct)%   mem ($mem)   up ($up)"
}

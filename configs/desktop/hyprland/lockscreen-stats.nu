#!/usr/bin/env -S nu --no-config-file
# the lock screen's one stats line: kernel, load as a share of the cores, memory, uptime

def main [] {
    let load = open /proc/loadavg | split row " " | first | into float
    let cpu = $load * 100 / (sys cpu | length) | math round
    let mem = ^free -h --si | lines | where $it starts-with "Mem:" | first | split row --regex '\s+' | $"($in.2)/($in.1)"
    let up = ^uptime -p | str replace --regex '^up ' "" | str replace --regex ' hours?' "h" | str replace --regex ' minutes?' "m"
        | str replace --all "," ""
    print $"(^uname -r | str trim)   cpu ($cpu)%   mem ($mem)   up ($up)"
}

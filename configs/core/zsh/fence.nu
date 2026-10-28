#!/usr/bin/env -S nu --no-config-file

const OOM_SCORE_ADJ = 1000
const NICENESS = 19
const CPU_WEIGHT = 10

# The cpus whose l3 is smaller than the largest: the non-v-cache ccd on an x3d part, none on a uniform cpu.
def cpus-build []: nothing -> list<string> {
    let caches = glob /sys/devices/system/cpu/cpu[0-9]*/cache/index3/size | each {|f|
        {
            cpu: ($f | parse --regex 'cpu(?<n>\d+)/cache' | get 0.n)
            kb: (open --raw $f | parse --regex '^(?<n>\d+)' | get 0.n | into int)
        }
    }
    if ($caches | is-empty) { return [] }
    let max = $caches.kb | math max
    $caches | where kb < $max | get cpu
}

# Run a command at the lowest cpu and oom priority, pinned to the non-v-cache ccd where there is one.
def --wrapped main [...argv: string]: nothing -> nothing {
    if ($argv | is-empty) {
        print --stderr "usage: fence <command> [args...]"
        exit 2
    }
    let build = cpus-build
    let pin = if ($build | is-empty) { [] } else { [taskset -c ($build | str join ",")] }
    let pre = [choom -n $OOM_SCORE_ADJ --] ++ $pin ++ [nice $"-n($NICENESS)"]
    # the scope needs a reachable user manager, which a bare wsl root shell lacks
    if (do { ^systemctl --user show-environment } | complete).exit_code == 0 {
        exec systemd-run --user --scope --quiet -p $"CPUWeight=($CPU_WEIGHT)" ...$pre ...$argv
    }
    exec ...$pre ...$argv
}

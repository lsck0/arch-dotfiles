#!/usr/bin/env -S nu --no-config-file
# run a heavy build off the v-cache ccd, low priority and oom-first, in its own scope: under memory pressure
# systemd-oomd evicts the build, not the terminal, herdr session or agent that started it. a script, not a shell
# function, so agents' non-interactive shells reach it too. e.g. fence make -j / fence cargo build

const OOM_SCORE_ADJ = 1000
const NICENESS = 19
const CPU_WEIGHT = 10

# cpus whose l3 is smaller than the largest: the non-v-cache ccd on an x3d part, none on a uniform cpu
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

def --wrapped main [...argv: string]: nothing -> nothing {
    if ($argv | is-empty) {
        print --stderr "usage: fence <command> [args...]"
        exit 2
    }
    let build = cpus-build
    let pin = if ($build | is-empty) { [] } else { [taskset -c ($build | str join ",")] }
    let pre = [choom -n $OOM_SCORE_ADJ --] ++ $pin ++ [nice $"-n($NICENESS)"]
    # the cgroup scope needs a reachable user manager, which a bare wsl root shell lacks
    if (do { ^systemctl --user show-environment } | complete).exit_code == 0 {
        exec systemd-run --user --scope --quiet -p $"CPUWeight=($CPU_WEIGHT)" ...$pre ...$argv
    }
    exec ...$pre ...$argv
}

#!/usr/bin/env -S nu --no-config-file
# desktop-metrics' offload rows from worker states: running summed over users, each kind's newest finished job across
# users, malformed states and entries dropped; every name the rows carry has its HELP.

use scripts/desktop-metrics.nu [crashes-desktop offload-metrics]
use std/assert

const SCRIPT = path self scripts/desktop-metrics.nu
const NAMES = [worker_up jobs_running job_last_exit job_last_seconds job_last_peak_mib]

def value [rows: list<record>, name: string, labels: record = {}]: nothing -> any {
    $rows | where name == $name and labels == $labels | get --optional 0.value
}

# the crash metric keeps the desktop's own programs: a dev build and an agent's process (desktop session scope, Claude
# Code shell, scratch command) do not page; the two agent cases are the real false alarms of 2026-11-28
def crash-cases []: nothing -> nothing {
    let at = "1795800000000000"
    let dump = {|exe, cmdline, cgroup| {
        COREDUMP_EXE: $exe, COREDUMP_CMDLINE: $cmdline, COREDUMP_CGROUP: $cgroup, __REALTIME_TIMESTAMP: $at
    } }
    let app = "/user.slice/user-1000.slice/user@1000.service/app.slice"
    let entries = [
        (do $dump /usr/bin/firefox "/usr/bin/firefox" $"($app)/app-firefox.scope")
        (do $dump /usr/bin/magick "magick w.ppm -trim +repage w.png" $"($app)/app-com.anthropic.Claude-175706.scope")
        (do $dump /usr/bin/zsh "/usr/bin/zsh -c source /home/luca/.claude/shell-snapshots/snapshot-zsh-1.sh" $"($app)/app-graphical.slice/app-Hyprland-ghostty-1.scope")
        (do $dump /usr/bin/convert "convert /tmp/claude-1000/x/a.png b.png" $"($app)/app-ghostty.scope")
        (do $dump /home/luca/projects/nyangine/build "./build run test" $"($app)/run-p1.scope")
        (do $dump /usr/bin/clang-tidy "clang-tidy ./src/main.c" $"($app)/run-p3198359-i11561959.scope")
        ({COREDUMP_CWD: /home/luca/projects/x/.claude/worktrees/wf_1} | merge (do $dump /usr/bin/python3 "python -c 1" $"($app)/app-ghostty.scope"))
        {COREDUMP_CMDLINE: "no exe"}
    ]
    assert equal ($entries | crashes-desktop) [{program: firefox, time: 1795800000}] "only firefox's crash is the desktop's"
}

def main [] {
    crash-cases
    let none = offload-metrics false []
    assert equal ($none | select name value) [[name value]; [worker_up 0] [jobs_running 0]] "no states"

    let lab = {running: 1, last: {
        static-site: {exit: 0, seconds: 40, peakMiB: 900, ended: 200}
        arch-base: {exit: 2, seconds: 3000, peakMiB: 6000, ended: 100}
    }}
    let owner = {running: 2, last: {
        static-site: {exit: 1, seconds: 5, peakMiB: 100, ended: 150}
        run: {exit: 0, seconds: 60, peakMiB: 2000, ended: 300}
    }}
    let broken = [
        "text" {running: "1", last: {}} {running: 1} {running: 1, last: {run: {exit: "0", seconds: 1, peakMiB: 1, ended: 999}}}
        {running: 0, last: {bogus: {exit: 0, seconds: 1, peakMiB: 1, ended: 999}}}
    ]
    let rows = offload-metrics true ([$lab $owner] ++ $broken)
    assert equal (value $rows worker_up) 1
    assert equal (value $rows jobs_running) 4 "running: the valid states summed, the malformed ones' left out"
    assert equal (value $rows job_last_exit {kind: static-site}) 0 "static-site: the newest of both users"
    assert equal (value $rows job_last_seconds {kind: static-site}) 40
    assert equal (value $rows job_last_peak_mib {kind: arch-base}) 6000
    assert equal (value $rows job_last_exit {kind: run}) 0 "run: the string exit's entry dropped"
    assert equal ($rows | where labels.kind? == bogus | length) 0 "an unknown kind made rows"
    assert ($rows | all { $in.type == gauge }) "every offload row is a gauge"

    # each name is in HELP: the exposition would fail on a missing one
    let help = open --raw $SCRIPT | parse --regex '(?m)^\s+(?<name>[a-z_]+): "' | get name
    for name in $NAMES { assert ($name in $help) $"($name) has no HELP" }
}

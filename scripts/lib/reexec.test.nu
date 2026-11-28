#!/usr/bin/env -S nu --no-config-file
# The state lock dot.nu takes before it hands an apply on: the argv it is given runs under the flock with DOT_LOCK
# naming it, and a run that already holds the lock goes on without a re-exec.
use std/assert

# A shell that prints DOT_LOCK and whether the lock is free to a third process.
def probe [lock: path]: nothing -> list<string> {
    [sh -c $"echo \"$DOT_LOCK\"; if flock --nonblock '($lock)' true; then echo free; else echo held; fi"]
}

def hold [state: path, argv: list<string>, --held: string]: nothing -> record {
    let call = $"use reexec.nu [user-locked]; user-locked --argv ($argv | to nuon); print returned"
    let env_extra = {XDG_STATE_HOME: $state} | merge (if $held != null { {DOT_LOCK: $held} } else { {} })
    with-env $env_extra { "" | ^$nu.current-exe --no-config-file -I ($env.FILE_PWD) -c $call | complete }
}

def lock-cases [dir: path]: nothing -> nothing {
    let state = $dir | path join state
    let lock = $state | path join dotfiles run.lock
    let run = hold $state (probe $lock)
    assert equal $run.exit_code 0 $run.stderr
    assert equal ($run.stdout | lines) [$lock held] "the argv did not run under run.lock with DOT_LOCK naming it"
    let nested = hold $state (probe $lock) --held $lock
    assert equal ($nested.stdout | lines) [returned] "a run already holding run.lock re-execed under it again"
}

def main [] {
    let dir = mktemp --directory --tmpdir dot-reexec-test-XXXXXX
    try { lock-cases $dir } catch {|e|
        rm --recursive --force $dir
        error make $e
    }
    rm --recursive --force $dir
}

# The re-exec under interruptible.sh and the state locks it holds. A module of its own: module.nu defines an `exec`,
# which shadows the builtin in every file module.nu imports, state.nu among them; and dot.nu takes run.lock from here,
# a parse of a few milliseconds, before it hands an apply on.

use state.nu [state-dir]
use proc.nu [succeeds]

const SUPERVISOR = path self interruptible.sh

# This process's argv, to re-exec it.
export def self-argv []: nothing -> list<string> {
    open --raw $"/proc/($nu.pid)/cmdline" | into binary | decode utf-8 | split row (char nul) | drop 1
}

# Re-execs under interruptible.sh so ctrl+c ends the run; --lock holds a flock that nested runs skip.
export def supervise [--lock: path, --argv: list<string>]: nothing -> nothing {
    let argv = $argv | default (self-argv)
    if $lock == null {
        if not (is-terminal --stdin) { return }
        if ($env.DOT_INTERRUPTIBLE? | default "") == (^ps -o sid= -p $nu.pid | str trim) { return }
        exec $SUPERVISOR ...$argv
    }
    let held = locks-held
    if $lock in $held { return }
    mkdir ($lock | path dirname)
    exec $SUPERVISOR --lock $lock env $"DOT_LOCK=($held | append $lock | str join (char esep))" ...$argv
}

# The flocks this process and its parents hold, from DOT_LOCK: a run can hold several, each taken by one re-exec.
export def locks-held []: nothing -> list<string> {
    $env.DOT_LOCK? | default "" | split row (char esep) | where $it != ""
}

# Holds <state dir>/name for the rest of the run, re-execing argv (default this process's) under it; while another run
# holds it, says "dot: <busy>, waiting for it".
export def state-lock-hold [name: string, busy: string, --argv: list<string>]: nothing -> nothing {
    let lock = state-dir | path join $name
    if $lock not-in (locks-held) and ($lock | path exists) and not (succeeds flock --nonblock $lock true) {
        print -e $"dot: ($busy), waiting for it"
    }
    supervise --lock $lock --argv=$argv
}

# Holds run.lock, the user layer's, for the rest of the run. dot.nu takes it with the argv it hands an apply on, before
# that process parses the pipeline, so the re-exec under the lock never pays the parse twice.
export def user-locked [--argv: list<string>]: nothing -> nothing {
    state-lock-hold run.lock "another dot run holds the user layer" --argv=$argv
}

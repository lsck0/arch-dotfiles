# The dot CLI's shared plumbing: job count, build identity, and the guarded run with its crash record.

use log.nu *

const REPO = path self ../..
const CRASH_LOG_LINES = 20
const SUPERVISOR = path self interruptible.sh

# Flattens a list of lists by one level.
export def concat []: list -> list {
    reduce --fold [] {|part, acc| $acc ++ $part }
}

# Parallel jobs: DOTFILES_JOBS, else the cpu count.
export def jobs []: nothing -> int {
    let jobs = $env.DOTFILES_JOBS? | default (sys cpu | length) | into int
    if $jobs < 1 { error make {msg: $"DOTFILES_JOBS=($jobs) is not a positive number"} }
    $jobs
}

# The checkout's commit, whether it is dirty, and the nushell version.
export def build []: nothing -> record {
    let head = try { ^git -C $REPO rev-parse --short=12 HEAD | str trim } catch { "none" }
    let dirty = (try { ^git -C $REPO status --porcelain --ignore-submodules=all | str trim } catch { "" }) | is-not-empty
    {commit: $head, dirty: $dirty, nu: (version | get version)}
}

# This process's argv, to re-exec it.
export def self-argv []: nothing -> list<string> {
    open --raw $"/proc/($nu.pid)/cmdline" | into binary | decode utf-8 | split row (char nul) | drop 1
}

# Re-execs this command line once under interruptible.sh, so ctrl+c ends the run; without --lock only from a
# terminal. --lock holds that flock for the run, and a dot below it on the same lock skips it.
export def supervise [--lock: path, --argv: list<string>]: nothing -> nothing {
    let argv = $argv | default (self-argv)
    if $lock == null {
        if not (is-terminal --stdin) { return }
        if ($env.DOT_INTERRUPTIBLE? | default "") == (^ps -o sid= -p $nu.pid | str trim) { return }
        exec $SUPERVISOR ...$argv
    }
    if ($env.DOT_LOCK? | default "") == $lock { return }
    mkdir ($lock | path dirname)
    exec $SUPERVISOR --lock $lock env $"DOT_LOCK=($lock)" ...$argv
}

# Runs body as one logged run; an unexpected error leaves crash.json; ctrl+c ends it (supervise).
# --read-only: its log never evicts one that changed something, and ctrl+c is nushell's own.
# --background: a helper run (gen, fetch, update, backup) that may write but is no apply: it is kept with the read-only
# runs, so `dot log` and `dot status` keep pointing at the last real apply.
export def guarded [name: string, body: closure, --read-only, --background]: nothing -> any {
    if not $read_only { supervise }
    run-begin $name --read-only=($read_only or $background) | ignore
    $env.DOTFILES = $REPO
    $env.LOG_TAG = "dot"
    try {
        span $name {} $body
    } catch {|err|
        if ($err.debug | str starts-with "LabeledError") {
            log-err $err.msg
            run-journal
            exit 1
        }
        # the reader went away (`dot status | head`): nothing failed, so no crash record; 141 is a SIGPIPE exit
        if ($err.debug | str contains "BrokenPipe") {
            run-journal
            exit 141
        }
        # ctrl+c is no crash: the supervisor logs the interrupt, nothing goes to crash.json
        if ($err.debug | str contains "Interrupted") or ($err.msg | str lowercase | str contains "interrupted") {
            run-journal
            exit 130
        }
        let run = $env.DOT_RUN_FILE
        let file = $run | path dirname | path dirname | path join crash.json
        let tail = if ($run | path exists) { open --raw $run | lines | last $CRASH_LOG_LINES } else { [] }
        {run: $env.DOT_RUN_ID, command: $name, error: $err.msg, debug: $err.debug, rendered: $err.rendered, build: (build), log: $tail} | save --force $file
        log-record PANIC $"(error-brief $err.rendered --root $REPO); the full error is in ($file)" {msg_detail: $err.msg}
        run-journal
        exit 1
    }
}

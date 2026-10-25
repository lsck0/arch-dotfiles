# The dot CLI's shared plumbing: job count, build identity, and the guarded run with its crash record.

use log.nu *

const REPO = path self ../..
const CRASH_LOG_LINES = 20

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

# Re-execs this command under interruptible.sh unless one already watches this session: nushell's try
# would swallow a ctrl+c and run the later phases. A session without a terminal has no ctrl+c.
export def interruptible []: nothing -> nothing {
    if not (is-terminal --stdin) { return }
    if ($env.DOT_INTERRUPTIBLE? | default "") == (^ps -o sid= -p $nu.pid | str trim) { return }
    exec ($REPO | path join scripts lib interruptible.sh) ...(self-argv)
}

# Runs body as one logged run; an unexpected error leaves crash.json; ctrl+c ends it (interruptible).
# --read-only: its log never evicts one that changed something, and ctrl+c is nushell's own.
export def guarded [name: string, body: closure, --read-only]: nothing -> any {
    if not $read_only { interruptible }
    run-begin $name --read-only=$read_only | ignore
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
        let run = $env.DOT_RUN_FILE
        let file = $run | path dirname | path dirname | path join crash.json
        let tail = if ($run | path exists) { open --raw $run | lines | last $CRASH_LOG_LINES } else { [] }
        {run: $env.DOT_RUN_ID, command: $name, error: $err.msg, debug: $err.debug, rendered: $err.rendered, build: (build), log: $tail} | save --force $file
        log-record PANIC $"(error-brief $err.rendered --root $REPO); the full error is in ($file)" {msg_detail: $err.msg}
        run-journal
        exit 1
    }
}

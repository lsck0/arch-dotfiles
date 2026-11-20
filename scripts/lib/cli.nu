# The dot CLI's shared plumbing: job count, build identity, and the guarded run with its crash record.

use log.nu *
use cause.nu [cause-from-error cause-text]
use state.nu [state-dir]

const REPO = path self ../..
const CRASH_LOG_LINES = 20
const SUPERVISOR = path self interruptible.sh
const CRASH_FILE = "crash.json"
# wider than any row: the piped table is never wrapped or truncated
const ROWS_PIPED_WIDTH = 100_000

# A switch as the argv it was given: [--name] when on.
export def flag [name: string, on: bool]: nothing -> list<string> {
    if $on { [$"--($name)"] } else { [] }
}

# A command's rows: the table at a terminal; piped, borderless at full width, one row a line, where nushell's own table
# wraps a cell to 80 columns and grep finds half an id.
export def rows-out []: table -> any {
    let rows = $in
    if (is-terminal --stdout) { $rows } else { $rows | table --theme none --index false --width $ROWS_PIPED_WIDTH }
}

# Parallel jobs: DOTFILES_JOBS, else the cpu count.
export def jobs []: nothing -> int {
    let raw = $env.DOTFILES_JOBS? | default (sys cpu | length)
    let jobs = try { $raw | into int } catch { 0 }
    if $jobs < 1 { error make {msg: $"DOTFILES_JOBS=($raw) is not a positive number"} }
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

# The crash record next to a runs dir.
export def crash-file [runs: path]: nothing -> path {
    $runs | path dirname | path join $CRASH_FILE
}

# A crash record, null without a readable one.
export def crash-read [file: path]: nothing -> any {
    try { open --raw $file | from json } catch { null }
}

# Every unresolved crash in a record, newest first: the top-level one and the other commands' under `others`.
export def crash-list [record: any]: nothing -> list<record> {
    if $record == null { return [] }
    [($record | reject --optional others)] ++ ($record.others? | default [])
}

# The record holding crashes (newest first): the newest at the top level, so a reader of one crash reads it, the rest
# of the other commands' under `others`; null for none.
def crash-record [crashes: list<record>]: nothing -> any {
    if ($crashes | is-empty) { return null }
    let rest = $crashes | skip 1
    if ($rest | is-empty) { $crashes.0 } else { $crashes.0 | insert others $rest }
}

def crash-save [file: path, crashes: list<record>]: nothing -> nothing {
    let record = crash-record $crashes
    if $record == null { rm --force $file } else { $record | to json | save --force $file }
}

# Whether a run of <name> that goes through resolves crash c: a --read-only run (`dot internal theme list`,
# `dot set --json`) only a read-only crash, a writer of that name still fails.
def crash-resolves [c: record, name: string, read_only: bool]: nothing -> bool {
    $c.command? == $name and (not $read_only or ($c.read_only? | default false))
}

# Drops the crash of <name>: its run went through. Another command's unresolved crash stays.
export def crash-retire [name: string, --read-only]: nothing -> nothing {
    let crash = crash-file ($env.DOT_RUN_FILE | path dirname)
    let crashes = crash-list (crash-read $crash)
    if ($crashes | any {|c| crash-resolves $c $name $read_only }) { crash-save $crash ($crashes | where {|c| not (crash-resolves $c $name $read_only) }) }
}

# One logged run, crash.json on error, which the command's next run that goes through retires. --read-only and
# --background runs never replace the last apply.
export def guarded [name: string, body: closure, --read-only, --background]: nothing -> any {
    if not $read_only { supervise }
    run-begin $name --read-only=($read_only or $background) | ignore
    $env.DOTFILES = $REPO
    $env.LOG_TAG = "dot"
    let crash = crash-file ($env.DOT_RUN_FILE | path dirname)
    try {
        let value = span $name {} $body
        crash-retire $name --read-only=$read_only
        $value
    } catch {|err|
        let code = if ($err.debug | str starts-with "LabeledError") {
            log-err $err.msg
            1
        } else if ($err.debug | str contains "BrokenPipe") {
            # the reader went away (`dot status | head`): nothing failed, so no crash record; 141 is a SIGPIPE exit
            141
        } else if ($err.debug | str contains "Interrupted") {
            # ctrl+c is no crash: the supervisor logs the interrupt, nothing goes to crash.json
            130
        }
        if $code != null {
            run-journal
            exit $code
        }
        let run = $env.DOT_RUN_FILE
        let tail = if ($run | path exists) { open --raw $run | lines | last $CRASH_LOG_LINES } else { [] }
        let cause = cause-from-error $err
        let brief = if $cause.command != null or $cause.at != null or $cause.exit_code != null { cause-text $cause } else { error-brief $err.rendered --root $REPO }
        let record = {run: $env.DOT_RUN_ID, command: $name, read_only: $read_only, error: $err.msg, cause: $cause, debug: ($err.debug | ansi strip), rendered: ($err.rendered | ansi strip), build: (build), log: $tail}
        # one file per layer: a crash of one command must not overwrite another's that is still unresolved
        crash-save $crash ([$record] ++ (crash-list (crash-read $crash) | where {|c| not (crash-resolves $c $name $read_only) }))
        log-record PANIC $"($brief); the full error is in ($crash)" {msg_detail: $err.msg, cause: $cause}
        run-journal
        exit 1
    }
}

# The variables an agent harness sets in its shells (Claude Code, generic, Gemini, Copilot); the shell rcs spell them too.
const AGENT_MARKERS = [CLAUDECODE AI_AGENT GEMINI_CLI COPILOT_CLI_BINARY_VERSION]

def agent-session []: nothing -> bool {
    $AGENT_MARKERS | any {|name| $env | get --optional $name | is-not-empty }
}

# How this process reaches root: sudo at a terminal a person sees, pkexec's dialog in a graphical session otherwise,
# null with neither. An agent's shell (Luca's ! commands in Claude Code too) holds a terminal nobody sees, so sudo's
# touch cue and password prompt would land there unread; its dialog is visible and asks the same key.
export def root-runner []: nothing -> any {
    let seen_terminal = (is-terminal --stdin) and not (agent-session)
    let graphical = ($env.WAYLAND_DISPLAY? | is-not-empty) or ($env.DISPLAY? | is-not-empty)
    if $seen_terminal { "sudo" } else if $graphical and (which pkexec | is-not-empty) { "pkexec" } else { null }
}

# Holds <state dir>/name for the rest of the run; while another run holds it, says "dot: <busy>, waiting for it".
export def state-lock-hold [name: string, busy: string]: nothing -> nothing {
    let lock = state-dir | path join $name
    if $lock not-in (locks-held) and ($lock | path exists) and (^flock --nonblock $lock true | complete).exit_code != 0 {
        print -e $"dot: ($busy), waiting for it"
    }
    supervise --lock $lock
}

# Held by every writer of modules/<id>/theme.nuon outside a dot apply: dot-theme.service's theme apply and an unlink's
# theme row. Taken after run.lock, never before, and dot apply, which waits on that unit, never takes it.
export def theme-locked []: nothing -> nothing {
    state-lock-hold theme.lock "a theme switch is running"
}

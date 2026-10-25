# Logging: lines to stderr at DOT_LOG's level and every record as json into the run's file
# <runs>/<id>.jsonl, with spans for dot log --trace.

use state.nu [state-dir SYSTEM_STATE]

const LEVELS = [TRACE DEBUG INFO WARN ERROR PANIC]
const RUNS_KEEP = 50
const RUNS_READ_ONLY_KEEP = 20
const RUN_READ_ONLY_MARK = '"read_only":true'
const STREAM_TAIL_LINES = 5

def rank [level: string]: nothing -> int {
    $LEVELS | enumerate | where item == ($level | str uppercase) | get 0.index
}

export def since-ms [start: datetime]: nothing -> int {
    (date now) - $start | into int | $in // 1_000_000
}

export def runs-dir []: nothing -> path {
    if (is-admin) { $SYSTEM_STATE | path join runs } else { with-env {DOT_LAYER: user} { state-dir | path join runs } }
}

# Prints message at or above DOT_LOG and appends it with fields to the run file, if a run is open.
export def log-record [level: string, message: string, fields: record = {}]: nothing -> nothing {
    if (rank $level) >= (rank ($env.DOT_LOG? | default INFO)) {
        let prefix = if $level == "INFO" { "" } else { $"($level | str lowercase): " }
        print -e $"($env.LOG_TAG? | default dotfiles): ($prefix)($message)"
    }
    if ($env.DOT_RUN_FILE? | is-empty) { return }
    {
        time: (date now | format date "%+")
        level: $level
        run: $env.DOT_RUN_ID
        span: ($env.DOT_SPAN? | default "")
        module: ($env.DOTFILES_MODULE? | default "")
        verb: ($env.DOT_VERB? | default "")
        msg: $message
    } | merge $fields | $"($in | to json --raw)\n" | save --append $env.DOT_RUN_FILE
}

export def log-debug [message: string, fields: record = {}]: nothing -> nothing { log-record DEBUG $message $fields }
export def log-info [message: string, fields: record = {}]: nothing -> nothing { log-record INFO $message $fields }
export def log-warn [message: string, fields: record = {}]: nothing -> nothing { log-record WARN $message $fields }
# Something the person has to do, not a fault.
export def log-note [message: string, fields: record = {}]: nothing -> nothing { log-record INFO $"note: ($message)" ($fields | merge {kind: note}) }
export def log-err [message: string, fields: record = {}]: nothing -> nothing { log-record ERROR $message $fields }

# Runs argv with its output streamed under tag and kept; setsid and no stdin, since under dot's pty a
# background command touching the terminal is stopped for good.
export def command-stream [tag: string, argv: list]: nothing -> record {
    let log = mktemp --tmpdir
    let code = try {
        null | ^setsid --wait ...$argv o+e>| tee { save --force $log } | lines | each {|l| print -e $"($tag) | ($l)" } | ignore
        0
    } catch {|e| if $e.exit_code? == null { rm $log; $e.raw } else { $e.exit_code } }
    let output = open --raw $log
    rm $log
    {exit_code: $code, output: $output, tail: ($output | lines | last $STREAM_TAIL_LINES | str join "\n")}
}

# Logs message as a failure and appends it to FAILURES_FILE, falling back to the run's own
# failures path when no phase has opened one (a crash here must never take down the whole run).
export def fail [message: string]: nothing -> nothing {
    log-err $message {kind: failure}
    let target = if ($env.FAILURES_FILE? | is-empty) { $env.DOT_RUN_FILE | str replace ".jsonl" ".failures" } else { $env.FAILURES_FILE }
    $"($message)\n" | save --append $target
}

def runs-list []: nothing -> record {
    let files = glob (runs-dir | path join "*.jsonl") | sort
    let read_only = if ($files | is-empty) { [] } else { ^grep --files-with-matches --fixed-strings $RUN_READ_ONLY_MARK ...$files | complete | get stdout | lines }
    {files: $files, read_only: $read_only}
}

# The newest run file that could change something, null without one.
export def run-last-changed []: nothing -> any {
    let runs = runs-list
    $runs.files | where $it not-in $runs.read_only | last
}

# Opens a run file and prunes old ones, keeping RUNS_KEEP changing and RUNS_READ_ONLY_KEEP read-only runs.
export def --env run-begin [name: string, --read-only]: nothing -> nothing {
    $env.DOT_RUN_ID = $"(date now | format date '%Y%m%dT%H%M%S')-(random chars --length 4 | str lowercase)"
    $env.DOT_RUN_FILE = runs-dir | path join $"($env.DOT_RUN_ID).jsonl"
    $env.DOT_SPAN = ""
    mkdir (runs-dir)
    let pointer = $env.DOT_RUN_POINTER? | default ""
    if $pointer != "" and ($pointer | path exists) and (open --raw $pointer | is-empty) { $env.DOT_RUN_FILE | save --force $pointer }
    let runs = runs-list
    let changing = $runs.files | where $it not-in $runs.read_only
    ($changing | drop $RUNS_KEEP) ++ ($runs.read_only | drop $RUNS_READ_ONLY_KEEP) | each { rm --force $in } | ignore
    log-debug $"run ($name)" {kind: run, target: $name, read_only: $read_only}
}

# Runs body as a traced span; child processes inherit it, and an error still closes it before rethrowing.
export def span [name: string, fields: record, body: closure]: nothing -> any {
    let id = random chars --length 8 | str lowercase
    let start = date now
    let base = {span: $id, parent: ($env.DOT_SPAN? | default ""), kind: span, target: $name} | merge $fields
    with-env {DOT_SPAN: $id} {
        log-record TRACE $"begin ($name)" ($base | insert phase begin)
        let result = try { {ok: true, value: (do $body)} } catch {|err| {ok: false, error: $err} }
        let ms = since-ms $start
        log-record TRACE $"end ($name)" ($base | merge {phase: end, ms: $ms, outcome: (if $result.ok { "ok" } else { "error" })})
        if not $result.ok { $result.error.raw }
        $result.value
    }
}

const ERROR_AT = '\[(?<file>[^\]\s]+):(?<line>\d+):\d+\]'
const ERROR_MARK = '^(x|×) '

# One line from a rendered nushell error: the first file:line it points at, then its message.
export def error-brief [rendered: string, --root: path]: nothing -> string {
    let rows = $rendered | lines | str trim | where $it != ""
    let message = $rows | where $it =~ $ERROR_MARK | get --optional 0 | default ($rows | get --optional 0 | default "unknown error") | str replace --regex $ERROR_MARK "" | str trim --right --char "."
    let at = $rendered | parse --regex $ERROR_AT | where file != "<commandline>" | get --optional 0
    if $at == null { return $message }
    let file = if $root != null and ($at.file | str starts-with $"($root)/") { $at.file | path relative-to $root } else { $at.file }
    $"($file):($at.line): ($message)"
}

# Sends the run's records at INFO and above to the journal as SYSLOG_IDENTIFIER=dot.
export def run-journal []: nothing -> nothing {
    if ($env.DOT_RUN_FILE? | is-empty) or not ($env.DOT_RUN_FILE | path exists) { return }
    open --raw $env.DOT_RUN_FILE | lines | each { from json } | where {|r| (rank $r.level) >= (rank INFO) } | each {|r|
        [
            $"MESSAGE=($r.msg | str replace --all "\n" ' ')"
            $"PRIORITY=(match $r.level { 'WARN' => 4, 'ERROR' => 3, 'PANIC' => 2, _ => 6 })"
            "SYSLOG_IDENTIFIER=dot"
            $"DOT_RUN=($r.run)"
            $"DOT_MODULE=($r.module? | default '')"
            $"DOT_TARGET=($r.target? | default '' | into string | str replace --all "\n" ' ')"
        ] | str join "\n" | ^logger --journald
    } | ignore
}

use state.nu [state-dir SYSTEM_STATE]

const LEVELS = [TRACE DEBUG INFO WARN ERROR PANIC]
const RUNS_KEEP = 50
const STREAM_TAIL_LINES = 5

def rank [level: string]: nothing -> int {
    $LEVELS | enumerate | where item == ($level | str uppercase) | get 0.index
}

export def runs-dir []: nothing -> path {
    if (is-admin) { $SYSTEM_STATE | path join runs } else { with-env {DOT_LAYER: user} { state-dir | path join runs } }
}

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
# something the person has to do, not a fault
export def log-note [message: string, fields: record = {}]: nothing -> nothing { log-record INFO $"note: ($message)" ($fields | merge {kind: note}) }
export def log-err [message: string, fields: record = {}]: nothing -> nothing { log-record ERROR $message $fields }

# setsid, no stdin: under dot's pty a background command that touches the terminal (claude's cli) is stopped for good
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

export def fail [message: string]: nothing -> nothing {
    log-err $message {kind: failure}
    $"($message)\n" | save --append $env.FAILURES_FILE
}

export def --env run-begin [name: string]: nothing -> nothing {
    $env.DOT_RUN_ID = $"(date now | format date '%Y%m%dT%H%M%S')-(random chars --length 4 | str lowercase)"
    $env.DOT_RUN_FILE = runs-dir | path join $"($env.DOT_RUN_ID).jsonl"
    $env.DOT_SPAN = ""
    mkdir (runs-dir)
    ls (runs-dir) | sort-by name | drop $RUNS_KEEP | each { rm --force $in.name } | ignore
    log-debug $"run ($name)" {kind: run, target: $name}
}

# child processes inherit the open span; an error still closes it
export def span [name: string, fields: record, body: closure]: nothing -> any {
    let id = random chars --length 8 | str lowercase
    let start = date now
    let base = {span: $id, parent: ($env.DOT_SPAN? | default ""), kind: span, target: $name} | merge $fields
    with-env {DOT_SPAN: $id} {
        log-record TRACE $"begin ($name)" ($base | insert phase begin)
        let result = try { {ok: true, value: (do $body)} } catch {|err| {ok: false, error: $err} }
        let ms = (date now) - $start | into int | $in // 1_000_000
        log-record TRACE $"end ($name)" ($base | merge {phase: end, ms: $ms, outcome: (if $result.ok { "ok" } else { "error" })})
        if not $result.ok { $result.error.raw }
        $result.value
    }
}

const ERROR_AT = '\[(?<file>[^\]\s]+):(?<line>\d+):\d+\]'
const ERROR_MARK = '^(x|×) '

# one line from a rendered nushell error: the first file:line it points at, then its message
export def error-brief [rendered: string, --root: path]: nothing -> string {
    let rows = $rendered | lines | str trim | where $it != ""
    let message = $rows | where $it =~ $ERROR_MARK | get --optional 0 | default ($rows | get --optional 0 | default "unknown error") | str replace --regex $ERROR_MARK "" | str trim --right --char "."
    let at = $rendered | parse --regex $ERROR_AT | where file != "<commandline>" | get --optional 0
    if $at == null { return $message }
    let file = if $root != null and ($at.file | str starts-with $"($root)/") { $at.file | path relative-to $root } else { $at.file }
    $"($file):($at.line): ($message)"
}

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

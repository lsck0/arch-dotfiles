use state.nu [state-dir SYSTEM_STATE]

const LEVELS = [TRACE DEBUG INFO WARN ERROR PANIC]
const RUNS_KEEP = 50

def rank [level: string]: nothing -> int {
    $LEVELS | enumerate | where item == ($level | str uppercase) | get 0.index
}

# the runner's own, whichever layer it plans
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
export def log-err [message: string, fields: record = {}]: nothing -> nothing { log-record ERROR $message $fields }

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

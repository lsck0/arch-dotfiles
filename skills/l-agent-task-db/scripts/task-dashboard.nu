#!/usr/bin/env -S nu --no-config-file
# Human-facing view of an l-agent-task-db taskwarrior instance: exactly what's queued, what stage every ticket is in,
# and what needs the human's input right now. Read-only: never modifies the db.
# The taskrc: <project-dir>/tasks/.taskrc if a project-dir is given, else $TASKRC if set, else ./tasks/.taskrc.

const RECENT_COMPLETED_LIMIT = 10
const DESC_MAX_CHARS = 50
const WIDTH_FALLBACK = 100
const ELLIPSIS = "..."
const QUESTIONS = "tasks/context/questions/"

def die [message: string]: nothing -> any {
    print -e $message
    exit 1
}

def taskrc-find [project?: path]: nothing -> path {
    if $project != null {
        let file = $project | path join tasks .taskrc
        if ($file | path type) != file { die $"error: no ($file)" }
        return ($file | path expand)
    }
    let env_file = $env.TASKRC? | default ""
    if $env_file != "" and ($env_file | path type) == file { return $env_file }
    if ("tasks/.taskrc" | path type) == file { return ("tasks/.taskrc" | path expand) }
    die "error: no tasks/.taskrc found (pass a project-dir, or cd into one with direnv/devenv active)."
}

# a cap that ends in the ellipsis, so a long or multi-line description never breaks the aligned layout
def clip [width: int]: string -> string {
    if ($in | str length -g) <= $width { return $in }
    ($in | str substring -g ..<([($width - ($ELLIPSIS | str length)) 0] | math max) | str trim --right) + $ELLIPSIS
}

def one-line []: string -> string {
    split row --regex '\s+' | where $it != "" | str join " " | clip $DESC_MAX_CHARS
}

def tags []: record -> list<string> { $in.tags? | default [] }

def stage-of []: record -> string {
    tags | where { str starts-with stage- } | get --optional 0 | default "stage--" | str substring 6..
}

def fmt []: record -> string {
    $"#($in.id | into string | fill --width 4) ($in.description | one-line)"
}

def where-line []: record -> string {
    $"  ($in | fmt)  [($in.project? | default '-')] [($in | stage-of)]"
}

def annotations []: record -> list<string> {
    $in.annotations? | default [] | get --optional description | default []
}

def question-file [root: path]: record -> any {
    let task = $in
    let noted = $task | annotations | where { str contains $QUESTIONS } | get --optional 0
    if $noted != null { return ($noted | split row "context: " | last) }
    # unannotated: the <uuid8>-<slug> file name
    glob ($root | path join tasks context questions $"($task.uuid | str substring ..<8)-*.md") | sort
        | get --optional 0 | if $in == null { null } else { $in | path relative-to $root }
}

def pr-link []: record -> any {
    $in | annotations | where { ($in | str starts-with "pr: ") or ($in | str contains /pull/) } | get --optional 0
        | if $in == null { null } else { $in | split row "pr: " | last }
}

def blocked-by [by_uuid: record]: record -> list<record> {
    $in.depends? | default [] | each {|u| $by_uuid | get --optional $u } | where $it.status not-in [completed deleted]
}

def main [project?: path]: nothing -> nothing {
    let taskrc = taskrc-find $project
    let tasks = with-env {TASKRC: $taskrc} { ^task rc.verbose=nothing export } | str trim
        | if $in == "" { [] } else { $in | from json }
    let by_uuid = $tasks | reduce --fold {} {|t, acc| $acc | insert $t.uuid $t }
    let color = is-terminal --stdout
    let columns = $env.COLUMNS? | default "" | into string
    let width = if $columns =~ '^\d+$' { $columns | into int } else if $color { (term size).columns } else {
        $WIDTH_FALLBACK
    }
    let out = {|line| print ($line | clip $width) }
    let hdr = {|title, n|
        let line = $"\n($title) \(($n)\)"
        print (if $color { $"(ansi attr_bold)($line)(ansi reset)" } else { $line })
    }

    let pending = $tasks | where status == pending
    let prompts = $pending | where { ("prompt" in ($in | tags)) and ("agent-task" not-in ($in | tags)) }
    let agent = $pending | where { "agent-task" in ($in | tags) }
    let root = $taskrc | path dirname --num-levels 2
    let gated = $agent | where { $in | tags | any { $in in [human-clarification-needed human-review-ready] } }
    let answered = $gated | where { ($in | tags) has human-answered and ($in | tags) has human-clarification-needed }
    let clarify = $gated | where { $in not-in $answered and ($in | tags) has human-clarification-needed }
    let review = $gated | where { $in not-in $answered and ($in | tags) has human-review-ready }
    let rest = $agent | where $it not-in $gated
    let active = $rest | where { $in.start? != null or ($in | stage-of) != "-" }
    let rest = $rest | where $it not-in $active
    let blocked = $rest | where { $in | blocked-by $by_uuid | is-not-empty }
    let ready = $rest | where $it not-in $blocked
    let done = $tasks | where { $in.status == completed and ($in | tags) has agent-task }
        | sort-by --reverse { $in.end? | default "" } | first $RECENT_COMPLETED_LIMIT

    print $"=== task db: ($root) ==="

    do $hdr "PROMPTS awaiting decomposition" ($prompts | length)
    for t in $prompts { do $out $"  ($t | fmt)" }
    if ($prompts | is-empty) { print "  (none)" }

    do $hdr "NEEDS CLARIFICATION" ($clarify | length)
    for t in $clarify {
        do $out ($t | where-line)
        let file = $t | question-file $root
        if $file != null { do $out $"        -> ($file)" }
    }

    do $hdr "PR READY FOR YOUR REVIEW" ($review | length)
    for t in $review {
        do $out ($t | where-line)
        do $out $"        -> ($t | pr-link | default '(no PR annotated)')"
    }

    do $hdr "ANSWERED, AWAITING AGENT" ($answered | length)
    for t in $answered { do $out ($t | where-line) }

    do $hdr "IN PROGRESS" ($active | length)
    for t in $active {
        let started = if $t.start? != null { $"  \(started ($t.start)\)" } else { "  (paused)" }
        do $out $"($t | where-line)($started)"
    }

    do $hdr "READY (queued, unblocked)" ($ready | length)
    for t in ($ready | insert proj { $in.project? | default "(no project)" } | sort-by proj) {
        do $out $"  ($t | fmt)  [($t.proj)] [($t | stage-of)]"
    }

    do $hdr "BLOCKED (dependency not done)" ($blocked | length)
    for t in $blocked {
        let deps = $t | blocked-by $by_uuid | each { $"#($in.id) ($in.description | one-line)" } | str join ", "
        do $out ($t | where-line)
        do $out $"        waiting on: ($deps)"
    }

    do $hdr $"COMPLETED \(last ($RECENT_COMPLETED_LIMIT)\)" ($done | length)
    for t in $done { do $out $"  ($t.description | one-line)  [($t.project? | default '-')]  ($t.end? | default '')" }
}

#!/usr/bin/env -S nu --no-config-file

const HUMAN_TASKRC = ".config/task/taskrc"
const AGENT_DB_GLOB = "projects/*/tasks/.taskrc"
const READY_LIMIT = 10
const AGING_LIMIT = 10
const GITHUB_LIMIT = 15
const AGENT_DESC_MAX = 50
const PROJECT_TOP_TASKS = 2
const ACTIVE_TAG_LIMIT = 3
const BUGWARRIOR_TAG = "github"
const BUGWARRIOR_UDA = "githuburl"
const HUMAN_INPUT_TAGS = [human-clarification-needed human-review-ready]
const REVIEW_TAG_WORDS = [review approval]
const CLARIFY_TAG_WORDS = [needs-human clarification]

const REDRAW_INTERVAL = 1sec
const FAST_REFRESH = 5sec
const SLOW_REFRESH = 30sec
const COLUMN_RATIO = 0.5
const COLUMN_PAD = 3
const MIN_HEIGHT = 10
const MIN_WIDTH = 50
const BAR_PROJECT_W = 6
const BAR_TIME_W = 8
const STYLES = {normal: "", dim: "\e[38;5;245m", bold: "\e[1m", reverse: "\e[7m"}
const TABS = [Dashboard Review Clarify Due GitHub Agents Burndown]
const FOOTER_KEYS = " 1-7 Tab h l: tabs  j k: scroll  r: refresh  q: quit"
const SCREEN_ENTER = "\e[?1049h\e[?25l"
const SCREEN_LEAVE = "\e[?25h\e[?1049l"

def has [command: string]: nothing -> bool { which $command | is-not-empty }

# stdout without trailing newlines, empty when the command fails, so a broken subsystem never takes the page down
def --wrapped capture [...argv: string]: nothing -> string {
    do { ^$argv.0 ...($argv | skip 1) } | complete | get stdout | str trim --right --char "\n"
}

def run-json [...argv: string]: nothing -> list {
    try { capture ...$argv | from json | default [] } catch { [] }
}

def tasks-fetch [...filters: string]: nothing -> list {
    if (has task) { run-json task rc.verbose=nothing ...$filters export } else { [] }
}

def report [...args: string, --plain]: nothing -> string {
    capture task rc.verbose=nothing $"rc._forcecolor=(if $plain { 'off' } else { 'on' })" ...$args
}

def one-line [text: string]: nothing -> string { $text | str trim | split row --regex '\s+' | str join " " }

def desc-of [task: record]: nothing -> string { one-line ($task.description? | default "") }

def tags-of [task: record]: nothing -> list<string> { $task.tags? | default [] }

def has-tag-word [task: record, words: list<string>]: nothing -> bool {
    tags-of $task | any {|tag| $words | any {|w| $tag | str lowercase | str contains $w } }
}

def local-date [stamp: any]: nothing -> any {
    if $stamp == null { null } else { $stamp | into datetime | date to-timezone local | format date "%F" }
}

def today []: nothing -> string { date now | format date "%F" }

def is-ready [task: record]: nothing -> bool {
    $task.status? == pending and ($task.wait? == null or ($task.wait | into datetime) <= (date now))
}

def agent-db [taskrc: path]: nothing -> record {
    let root = $taskrc | path dirname --num-levels 2
    let name = $root | path basename
    let export = with-env {TASKRC: $taskrc} { do { ^task rc.verbose=nothing export } | complete }
    let all = try { $export.stdout | from json } catch { null }
    if $export.exit_code != 0 or $all == null { return {name: $name, note: "(unreadable db)"} }
    let open = $all | where { $in.status? == pending and "agent-task" in (tags-of $in) }
    if ($open | is-empty) { return {name: $name, note: "(no open agent tickets)"} }
    let gated = $open | where {|t| tags-of $t | any { $in in $HUMAN_INPUT_TAGS } }
    let waiting = $gated | where { "human-answered" not-in (tags-of $in) }
    let short = {|t|
        let text = one-line $t.description
        if ($text | str length) <= $AGENT_DESC_MAX { return $text }
        $"($text | str substring 0..<($AGENT_DESC_MAX - 3) | str trim --right)..."
    }
    let annotations = {|t| $t.annotations? | default [] | get description }
    {
        name: $name
        note: ""
        open: ($open | length)
        stages: ($open | each { tags-of $in | where { str starts-with stage- } | get --optional 0 | default "stage--" }
            | str substring 6.. | uniq --count | sort-by value | each { $"($in.value):($in.count)" } | str join " ")
        clarify: ($waiting | where { "human-clarification-needed" in (tags-of $in) } | each {|t|
            let annotated = do $annotations $t | where { str contains tasks/context/questions/ } | get --optional 0
            let link = if $annotated != null { $annotated | split row "context: " | last } else {
                glob ($root | path join tasks context questions $"($t.uuid | str substring 0..<8)-*.md") | sort
                | get --optional 0 | if $in == null { null } else { $in | path relative-to $root }
            }
            {id: $t.id, desc: (do $short $t), link: $link}
        })
        review: ($waiting | where { "human-review-ready" in (tags-of $in) } | each {|t|
            let pr = do $annotations $t | where { ($in | str starts-with "pr: ") or ($in | str contains /pull/) }
                | get --optional 0
            {id: $t.id, desc: (do $short $t), link: (if $pr == null { null } else { $pr | split row "pr: " | last })}
        })
        answered: ($gated | where { "human-answered" in (tags-of $in) } | length)
    }
}

def agent-dbs []: nothing -> list<record> {
    glob ($nu.home-dir | path join $AGENT_DB_GLOB) | sort | each { agent-db $in }
}

def github-issues [tasks: list]: nothing -> list {
    $tasks | where { $in.status? == pending }
    | where { ($in | get --optional $BUGWARRIOR_UDA | is-not-empty) or $BUGWARRIOR_TAG in (tags-of $in) }
    | sort-by { $in.project? | default "" } { $in.githubnumber? | default 0 }
}

def by-due-day [tasks: list, compare: closure]: nothing -> list {
    let day = today
    $tasks | where {|t| (is-ready $t) and $t.due? != null and (do $compare (local-date $t.due) $day) } | sort-by due
}

def aging [tasks: list]: nothing -> list {
    $tasks | where { is-ready $in } | sort-by { $in.entry? | default "" } | first $AGING_LIMIT
}

def next-up [state: record]: nothing -> list {
    let active = $state.active | get --optional uuid
    $state.tasks | where { (is-ready $in) and $in.start? == null and $in.uuid? not-in $active }
    | sort-by --reverse { $in.urgency? | default 0 }
}

def project-stats [tasks: list]: nothing -> list {
    $tasks | where { $in.project? | is-not-empty } | group-by project | items {|name, rows|
        let pending = $rows | where status == pending
        {
            name: $name
            pending: ($pending | length)
            completed: ($rows | where status == completed | length)
            top: ($pending | sort-by --reverse { $in.urgency? | default 0 } | first $PROJECT_TOP_TASKS)
        }
    } | where { $in.pending + $in.completed > 0 } | sort-by { -1 * $in.pending } name
}

def time-totals [entries: list]: nothing -> list {
    $entries | where start? != null | each {|e|
        let stop = if $e.end? == null { date now } else { $e.end | into datetime }
        let name = tags-of $e | str join ", " | if $in == "" { "(untagged)" } else { $in }
        {name: $name, secs: (($stop - ($e.start | into datetime)) / 1sec)}
    } | group-by name | items {|name, rows| {name: $name, secs: ($rows.secs | math sum)} } | sort-by --reverse secs
}

def agent-items [state: record, kind: string]: nothing -> list {
    $state.agents | where note == "" | each {|p| $p | get $kind | insert project $p.name } | flatten
}

def refresh-slow [state: record]: nothing -> record {
    $state | merge {
        tasks: (tasks-fetch)
        week: (if (has timew) { run-json timew export :week } else { [] })
        burndown: (if (has task) { report burndown.daily --plain } else { "" })
        agents: (agent-dbs)
        slow_at: (date now)
        updated: (date now | format date "%H:%M:%S")
    }
}

def refresh-fast [state: record]: nothing -> record {
    let latest = if (has timew) { run-json timew export @1 } else { [] }
    $state | merge {
        active: (tasks-fetch +ACTIVE)
        timer: ($latest | get --optional 0 | if $in != null and $in.end? == null { $in })
        fast_at: (date now)
    }
}

def line [text: string, style: string = normal]: nothing -> record { {s: $text, style: $style} }

def or-none [rows: list]: nothing -> list { if ($rows | is-empty) { [(line "  (none)" dim)] } else { $rows } }

def lines-github [issues: list, limit: int]: nothing -> list {
    $issues | first $limit | each {|t|
        let repo = [$t.githubrepo? $t.project? "-"] | where { is-not-empty } | first
        let ref = if ($t.githubnumber? | is-empty) { $repo } else { $"($repo)#($t.githubnumber | into int)" }
        let title = [$t.githubtitle? $t.description? ""] | where { is-not-empty } | first | str trim
        line $"  #($t.id | fill -w 4) ($ref | fill -w 28) ($title)"
    } | append (if ($issues | length) > $limit { line $"  ... and (($issues | length) - $limit) more" dim })
}

def lines-agent-flow [projects: list]: nothing -> list {
    if ($projects | is-empty) { return [(line "  (no agent task dbs under ~/projects)" dim)] }
    $projects | each {|p|
        if $p.note != "" { return [(line $"  ($p.name): ($p.note)" dim)] }
        [(line $"  ($p.name): ($p.open) open  [($p.stages)]")]
        | append ($p.clarify | each {|c|
            [(line $"      NEEDS YOU: #($c.id) ($c.desc)" bold)]
            | append (if $c.link != null { line $"                 -> ($c.link)" dim })
        } | flatten)
        | append ($p.review | each {|r|
            [
                (line $"      REVIEW PR: #($r.id) ($r.desc)" bold)
                (line $"                 -> ($r.link | default '(no PR annotated)')" dim)
            ]
        } | flatten)
        | append (if $p.answered > 0 { line $"      \(($p.answered) answered, awaiting agent\)" dim })
    } | flatten
}

def heading [text: string]: nothing -> string { capture gum style --bold --foreground 6 $">> ($text)" }

def section [title: string, body: string]: nothing -> list<string> {
    [(heading $title) (if ($body | str trim) == "" { "  (none)" } else { $body })]
}

def page []: nothing -> string {
    let title = $"TASK DASHBOARD // (date now | format date '%Y-%m-%d %H:%M')"
    let banner = capture gum style --border double --border-foreground 5 --padding "0 2" --bold --foreground 6 $title
    if not (has task) { return ([$banner "  taskwarrior not installed"] | str join "\n") }
    let timer = if (has timew) { capture timew | if $in == "" { "  (no active timer)" } else { $in } }
    let active = [$timer (report +ACTIVE)] | where { is-not-empty } | str join "\n"
    let issues = lines-github (github-issues (tasks-fetch)) $GITHUB_LIMIT | get s | str join "\n"
    [
        $banner
        (heading "ACTIVE (being worked now)")
        (if ($active | str trim) == "" { "  (none)" } else { $active })
        ...(section OVERDUE (report +OVERDUE))
        ...(section "DUE TODAY" (report due:today))
        ...(section "UPCOMING (ready)" (report $"limit:($READY_LIMIT)" ready))
        ...(section "AGING (oldest pending)" (report $"limit:($AGING_LIMIT)" aging))
        ...(section "GITHUB ISSUES (bugwarrior)" $issues)
        ...(section PROJECTS (report summary))
        ...(section "BURNDOWN (daily)" (report burndown.daily))
        ...(if (has timew) { section "TIME THIS WEEK" (capture timew summary :week) } else { [] })
        (heading "AGENT FLOW (per project)")
        (lines-agent-flow (agent-dbs) | get s | str join "\n")
    ] | where { is-not-empty } | str join "\n"
}

def put [y: int, x: int, text: string, style: string = normal]: nothing -> record {
    {y: $y, x: $x, s: $text, style: $style}
}

def truncate [text: string, width: int]: nothing -> string {
    if ($text | str length -g) <= $width { $text } else if $width > 3 {
        $"($text | str substring -g 0..<($width - 3))..."
    } else { $text | str substring -g 0..<([$width 0] | math max) }
}

def bar [filled: int, total: int]: nothing -> string {
    ("" | fill -c "=" -w $filled) + ("" | fill -c "." -w ($total - $filled))
}

def elapsed [start: any]: nothing -> string {
    if $start == null { return "" }
    let secs = (date now) - ($start | into datetime) | $in / 1sec | into int
    let days = $secs // 86400
    let pad = {|n| $n | fill -a r -c 0 -w 2 }
    let clock = $"($secs mod 86400 // 3600):(do $pad ($secs mod 3600 // 60)):(do $pad ($secs mod 60))"
    match $days { 0 => $clock, 1 => $"1 day, ($clock)", _ => $"($days) days, ($clock)" }
}

def hours [secs: number]: nothing -> string {
    let s = $secs | into int
    $"($s // 3600):($s mod 3600 // 60 | fill -a r -c 0 -w 2)"
}

def due-relative [task: record]: nothing -> string {
    if $task.due? == null { return "" }
    let days = ((local-date $task.due | into datetime) - (today | into datetime)) / 1day | into int
    match $days {
        -1 => "yesterday"
        0 => "today"
        1 => "tomorrow"
        $d if $d < -1 => $"(-1 * $d)d ago"
        $d => $"in ($d)d"
    }
}

def age [task: record]: nothing -> string {
    if $task.entry? == null { "" } else { $"(((date now) - ($task.entry | into datetime)) / 1day | into int)d" }
}

def priority-style [task: record]: nothing -> string {
    match $task.priority? { "H" => "bold", "L" => "dim", _ => "normal" }
}

def urgency [task: record]: nothing -> string { $task.urgency? | default 0 | into float | into string --decimals 1 }

def render-active [y0: int, x: int, w: int, rows: int, timer: any, tasks: list]: nothing -> record {
    mut ops = [(put $y0 $x ACTIVE dim)]
    mut y = $y0 + 1
    if $timer == null and ($tasks | is-empty) { return {y: ($y + 2), ops: ($ops | append (put $y $x "  -" dim))} }
    if $timer != null {
        let since = elapsed $timer.start?
        let label = $"timew: (tags-of $timer | str join ' ' | if $in == '' { '(untagged)' } else { $in })"
        $ops = $ops ++ [
            (put $y $x (truncate $label ($w - ($since | str length) - 2)) bold)
            (put $y ($x + $w - ($since | str length)) $since bold)
        ]
        $y += 2
    }
    for task in $tasks {
        if $y >= $rows - 3 { break }
        let since = elapsed $task.start?
        let meta = [$"#($task.id? | default 0)" $task.priority? (urgency $task) (due-relative $task)
            (if ($task.project? | is-empty) { null } else { $"@($task.project)" })]
            | where { is-not-empty } | append (tags-of $task | first $ACTIVE_TAG_LIMIT | each { $"+($in)" })
        $ops = $ops ++ [
            (put $y $x (truncate (desc-of $task) ($w - ($since | str length) - 2)) bold)
            (put $y ($x + $w - ($since | str length)) $since bold)
            (put ($y + 1) $x (truncate ($meta | str join "  ") $w) dim)
        ]
        $y += 3
    }
    {y: $y, ops: $ops}
}

def render-next [y0: int, x: int, w: int, rows: int, tasks: list]: nothing -> list {
    if ($tasks | is-empty) { return [(put $y0 $x NEXT dim) (put ($y0 + 1) $x "  -" dim)] }
    let id_w = 5
    let due_w = 10
    $tasks | first ([($rows - 1 - $y0 - 1) 0] | math max) | enumerate | each {|row|
        let t = $row.item
        let y = $y0 + 1 + $row.index
        let due = due-relative $t
        [
            (put $y $x ($t.id? | default 0 | fill -a r -w 3) dim)
            (put $y ($x + $id_w) (truncate (desc-of $t) ($w - $id_w - $due_w - 1)) (priority-style $t))
            (put $y ($x + $w - $due_w) ($due | fill -a r -w $due_w) dim)
        ]
    } | flatten | prepend (put $y0 $x NEXT dim)
}

def render-projects [y0: int, x: int, w: int, max_y: int, stats: list]: nothing -> record {
    mut ops = [(put $y0 $x PROJECTS dim)]
    mut y = $y0 + 1
    if ($stats | is-empty) { return {y: ($y + 2), ops: ($ops | append (put $y $x "  -" dim))} }
    let pct_w = 4
    let name_w = [1 ($w - $BAR_PROJECT_W - $pct_w - 2)] | math max
    for p in $stats {
        if $y >= $max_y - 1 { break }
        let percent = $p.completed / ($p.pending + $p.completed) * 100 | math round | into int
        let filled = $BAR_PROJECT_W * $percent / 100 | math round | into int
        $ops = $ops ++ [
            (put $y $x (truncate $p.name ($name_w - 1)))
            (put $y ($x + $name_w) (bar $filled $BAR_PROJECT_W) dim)
            (put $y ($x + $name_w + $BAR_PROJECT_W + 1) $"($percent | fill -a r -w 2)%" dim)
        ]
        $y += 1
        for t in $p.top {
            if $y >= $max_y - 1 { break }
            let desc = truncate (desc-of $t) ([1 ($w - 7)] | math max)
            $ops = $ops | append (put $y $x $"  ($t.id? | default 0 | fill -a r -w 3) ($desc)" dim)
            $y += 1
        }
    }
    {y: ($y + 1), ops: $ops}
}

def render-time [y0: int, x: int, w: int, rows: int, label: string, totals: list]: nothing -> record {
    let head = put $y0 $x $label dim
    if ($totals | is-empty) { return {y: ($y0 + 3), ops: [$head (put ($y0 + 1) $x "  -" dim)]} }
    let max_secs = $totals.0.secs
    let label_w = [1 ($w - $BAR_TIME_W - 7)] | math max
    let shown = $totals | first ([($rows - 1 - $y0 - 1) 0] | math max)
    let y = $y0 + 1 + ($shown | length)
    let ops = $shown | enumerate | each {|row|
        let ty = $y0 + 1 + $row.index
        let share = if $max_secs > 0 { $BAR_TIME_W * $row.item.secs / $max_secs | math round | into int } else { 1 }
        let filled = [1 $share] | math max
        [(put $ty $x (truncate $row.item.name ($label_w - 1)))
            (put $ty ($x + $label_w) (bar $filled $BAR_TIME_W) dim)
            (put $ty ($x + $label_w + $BAR_TIME_W + 1) (hours $row.item.secs) bold)]
    } | flatten
    {y: ($y + 2), ops: ([$head] ++ $ops ++ [(put $y ($x + $w - 6) (hours ($totals.secs | math sum)))])}
}

def render-dashboard [state: record, cols: int, rows: int]: nothing -> list {
    let col_x = $cols * $COLUMN_RATIO | into int
    let left_w = $col_x - $COLUMN_PAD
    let right_w = $cols - $col_x - $COLUMN_PAD - 1
    let rx = $col_x + $COLUMN_PAD
    let day = today
    let active = render-active 2 1 $left_w $rows $state.timer $state.active
    let projects = render-projects 2 $rx $right_w ($rows // 2 + 1) (project-stats $state.tasks)
    let todays = $state.week | where { $in.start? != null and (local-date $in.start) == $day }
    let today_time = render-time ($projects.y + 1) $rx $right_w $rows TODAY (time-totals $todays)
    let week_time = render-time ($today_time.y + 1) $rx $right_w $rows "THIS WEEK" (time-totals $state.week)
    let next = render-next ($active.y + 1) 1 $left_w $rows (next-up $state)
    let divider = 2..<($rows - 1) | each { put $in $col_x "|" dim }
    $divider ++ $active.ops ++ $next ++ $projects.ops ++ $today_time.ops ++ $week_time.ops
}

def lines-task-table [tasks: list]: nothing -> list {
    if ($tasks | is-empty) { return [(line "  No tasks in this category." dim)] }
    let row = {|id, pri, urg, project|
        $" ($id | fill -a r -w 3)  ($pri | fill -a r -w 3)  ($urg | fill -a r -w 4)  ($project | fill -w 15) "
    }
    [(line $"(do $row ID PRI URG PROJECT)DESCRIPTION" dim)] ++ ($tasks | each {|t|
        let tags = if (tags-of $t | is-empty) { "" } else { $" [(tags-of $t | str join ',')]" }
        let project = truncate ($t.project? | default "-" | if $in == "" { "-" } else { $in }) 14
        let text = do $row ($t.id? | default 0) ($t.priority? | default "-") (urgency $t) $project
        line $"($text)(desc-of $t)($tags)" (priority-style $t)
    })
}

def lines-agent-items [items: list]: nothing -> list {
    or-none ($items | each {|i|
        [(line $"  ($i.project) #($i.id) ($i.desc)" bold) (line $"      -> ($i.link | default '(none annotated)')" dim)]
    } | flatten)
}

def lines-due [tasks: list, label: string, describe: closure]: nothing -> list {
    let rows = $tasks | each {|t|
        let when = do $describe $t | fill -a r -w 10
        line $"  #($t.id? | default 0 | fill -w 4) ($when)  (desc-of $t)" (priority-style $t)
    }
    [(line $label bold)] ++ (or-none $rows) ++ [(line "")]
}

def pending-with [state: record, words: list<string>]: nothing -> list {
    $state.tasks | where { $in.status? == pending and (has-tag-word $in $words) }
}

def tab-lines [state: record, tab: string]: nothing -> list {
    match $tab {
        Review => ([(line "TASKS NEEDING REVIEW" bold)]
            ++ (lines-task-table (pending-with $state $REVIEW_TAG_WORDS))
            ++ [(line "") (line "AGENT PRS AWAITING REVIEW" bold)] ++ (lines-agent-items (agent-items $state review)))
        Clarify => ([(line "TASKS NEEDING CLARIFICATION (needs human input)" bold)]
            ++ (lines-task-table (pending-with $state $CLARIFY_TAG_WORDS))
            ++ [(line "") (line "AGENT TICKETS NEEDING YOU" bold)] ++ (lines-agent-items (agent-items $state clarify)))
        Due => ((lines-due (by-due-day $state.tasks {|due, day| $due < $day }) OVERDUE {|t| due-relative $t })
            ++ (lines-due (by-due-day $state.tasks {|due, day| $due == $day }) "DUE TODAY" {|t| due-relative $t })
            ++ (lines-due (aging $state.tasks) "AGING (oldest pending)" {|t| age $t }))
        GitHub => {
            let issues = github-issues $state.tasks
            [(line "GITHUB ISSUES (bugwarrior)" bold)] ++ (or-none (lines-github $issues ($issues | length)))
        }
        Agents => ([(line "AGENT FLOW (per project)" bold)] ++ (lines-agent-flow $state.agents))
        _ => ([(line "BURNDOWN (daily)" bold)] ++ (or-none ($state.burndown | lines | each { line $in })))
    }
}

def tab-count [state: record, tab: string]: nothing -> any {
    match $tab {
        Review => ((pending-with $state $REVIEW_TAG_WORDS | length) + (agent-items $state review | length))
        Clarify => ((pending-with $state $CLARIFY_TAG_WORDS | length) + (agent-items $state clarify | length))
        Due => (by-due-day $state.tasks {|due, day| $due <= $day } | length)
        GitHub => (github-issues $state.tasks | length)
        Agents => ($state.agents | get --optional open | compact | append 0 | math sum)
        _ => null
    }
}

def paint [ops: list, cols: int, rows: int]: nothing -> nothing {
    $ops | where { $in.y >= 0 and $in.y < $rows and $in.x >= 0 and $in.x < $cols - 1 }
    | each {|op|
        $"\e[($op.y + 1);($op.x + 1)H($STYLES | get $op.style)($op.s | str substring -g 0..<($cols - $op.x - 1))\e[0m"
    }
    | str join | $"\e[H\e[J($in)" | print --no-newline
}

def frame [state: record, tab: int, scroll: int, cols: int, rows: int]: nothing -> record {
    if $rows < $MIN_HEIGHT or $cols < $MIN_WIDTH {
        paint [(put 0 0 "terminal too small" bold)] $cols $rows
        return {scroll: $scroll}
    }
    let labels = $TABS | enumerate | each {|t|
        let count = tab-count $state $t.item | if $in == null { " " } else { $" \(($in)\) " }
        {text: $" ($t.index + 1):($t.item)($count)", style: (if $t.index == $tab { "reverse" } else { "dim" })}
    }
    let tab_ops = $labels | reduce --fold {x: 1, ops: []} {|l, acc|
        {x: ($acc.x + ($l.text | str length) + 1), ops: ($acc.ops | append (put 0 $acc.x $l.text $l.style))}
    } | get ops
    let body = if $tab == 0 { {ops: (render-dashboard $state $cols $rows), scroll: $scroll} } else {
        let all = tab-lines $state ($TABS | get $tab)
        let visible = $rows - 3
        let top = [0 ([$scroll (($all | length) - $visible)] | math min)] | math max
        let shown = $all | skip $top | first $visible | enumerate
        {ops: ($shown | each { put (2 + $in.index) 1 $in.item.s $in.item.style }), scroll: $top}
    }
    let updated = $"  updated ($state.updated) "
    let room = $cols - 1 - ($FOOTER_KEYS | str length)
    let footer = $FOOTER_KEYS + (if $room >= ($updated | str length) { $updated | fill -a r -w $room } else { "" })
    let body_ops = $body.ops | where y < $rows - 1
    let rule = put 1 0 ("" | fill -c "-" -w ($cols - 1)) dim
    paint ($tab_ops ++ [$rule] ++ $body_ops ++ [(put ($rows - 1) 0 $footer dim)]) $cols $rows
    {scroll: $body.scroll}
}

def tui []: nothing -> nothing {
    let never = 0 | into datetime
    mut state: record = {
        tasks: [], week: [], burndown: "", agents: [], active: [], timer: null
        slow_at: $never, fast_at: $never, updated: ""
    }
    mut tab = 0
    mut scroll = 0
    loop {
        if (date now) - $state.slow_at >= $SLOW_REFRESH {
            let rows = (term size).rows
            print --no-newline $"\e[($rows);1H\e[2K($STYLES.dim) refreshing...\e[0m"
            $state = refresh-slow $state
        }
        if (date now) - $state.fast_at >= $FAST_REFRESH { $state = refresh-fast $state }
        let size = term size
        $scroll = (frame $state $tab $scroll $size.columns $size.rows).scroll
        let event = try { input listen --types [key resize] --timeout $REDRAW_INTERVAL } catch { null }
        if $event == null or $event.type? != key { continue }
        let key = if $event.key_type == char { $event.code } else { $event.code | str lowercase }
        if $key in [q Q esc] or ($key == c and control in $event.modifiers) { break }
        match $key {
            r => { $state = $state | merge {slow_at: $never, fast_at: $never} }
            $d if $d =~ '^[1-7]$' => { $tab = ($d | into int) - 1; $scroll = 0 }
            tab | right | l => { $tab = ($tab + 1) mod ($TABS | length); $scroll = 0 }
            backtab | left | h => { $tab = ($tab + ($TABS | length) - 1) mod ($TABS | length); $scroll = 0 }
            down | j => { $scroll += 1 }
            up | k => { $scroll = [0 ($scroll - 1)] | math max }
            _ => {}
        }
    }
}

# Read-only dashboard of tasks, time, issues and agent task dbs: a TUI on a tty, else one printed page.
def main [
    --print # print one page instead of the TUI (default off a tty)
    --page (-p) # print one page through less
]: nothing -> nothing {
    # an agent shell may export its own TASKRC, the dashboard always reads the human db
    $env.TASKRC = $nu.home-dir | path join $HUMAN_TASKRC
    hide-env --ignore-errors TASKDATA TIMEWARRIORDB
    let tty = (is-terminal --stdout)
    if $print or $page or not $tty {
        let text = page
        if $page and $tty and (has less) { $"($text)\n" | ^less -R } else { print $text }
        return
    }
    print --no-newline $SCREEN_ENTER
    try { tui } finally { print --no-newline $SCREEN_LEAVE }
}

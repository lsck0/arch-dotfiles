#!/usr/bin/env -S nu --no-config-file
# Quick capture from the launcher (+ task, ! reminder, # note): one line in, a confirmation out.

const HERE = path self | path expand | path dirname
use ($HERE | path join lib shell.nu) [action-notify shell-call]

const INBOX = "sync/notes/inbox.md"
const TASK_GLYPH = "\u{f0ae}"
const NOTE_GLYPH = "\u{f0f6}"
const BELL_GLYPH = "\u{f009e}"
# AppSearch.qml sets it, so a failed capture reopens the launcher on the typed line
const LAUNCHER_ENV = "CAPTURE_FROM_LAUNCHER"
const TASK_SYNC_UNIT = "task-sync.service"

# the line as typed, in the notification so it can be copied back, and back in the launcher when it came from there
def capture-fail [glyph: string, title: string, reason: string, line: string]: nothing -> nothing {
    action-notify $glyph $title $"($reason)\n($line)"
    if ($env | get --optional $LAUNCHER_ENV) == "1" { try { shell-call appsearch openWith $line | ignore } }
    exit 1
}

# taskwarrior's compact UTC form, 20261120T230000Z
def task-date-format [value: string]: nothing -> string {
    let local = $value | str replace --regex 'Z$' '+0000' | into datetime --format '%Y%m%dT%H%M%S%z' | date to-timezone local
    $local | format date (if ($local | format date '%H:%M') == "00:00" { '%a %-d %b' } else { '%a %-d %b %-H:%M' })
}

# what taskwarrior stored, so a word it took as an attribute (re:) shows as missing
def task-summary [id: string]: nothing -> string {
    let task = ^task rc.verbose=nothing rc.json.array=on $id export | from json | first
    [
        $task.description
        ($task.project? | default "")
        (if $task.due? != null { $"due (task-date-format $task.due)" } else { "" })
        (if $task.scheduled? != null { $"scheduled (task-date-format $task.scheduled)" } else { "" })
    ] | where $it != "" | str join ", "
}

# --wrapped with untyped words: true, null, -v, --help, 0123 all reach taskwarrior as typed
# taskwarrior parses project:, due:, scheduled:, priority:, +tag itself; each word stays one argument
def --wrapped "main task" [...words]: nothing -> nothing {
    let words = $words | each { into string }
    if ($words | is-empty) { error make {msg: "nothing to add"} }
    let line = $"+ ($words | str join ' ')"
    let r = ^task rc.confirmation=no rc.verbose=new-id add ...$words | complete
    if $r.exit_code != 0 { capture-fail $TASK_GLYPH "Task not added" ($r.stderr | str trim) $line }
    let id = $r.stdout | parse --regex 'Created task (?<id>\d+)' | get --optional 0.id
    let summary = if $id == null { "" } else { try { task-summary $id } catch { "" } }
    action-notify $TASK_GLYPH "Task added" (if $summary != "" { $summary } else { $words | str join " " })
    try { shell-call tasks refresh | ignore }
    try { ^systemctl --user start --no-block $TASK_SYNC_UNIT o+e>| ignore }
}

# 90, 10m, 10min, 2h, 1h30m: whole minutes, null when it is not a duration; ReminderFlowModel.js minutesOf reads the same
export def minutes-of [text: string]: nothing -> any {
    let m = $text | parse --regex '(?i)^(?:(?<h>\d+)h)?(?:(?<m>\d+)(?:m|min|mins|minutes)?)?$' | get --optional 0
    # an unmatched optional group reads as null or empty depending on the nu version
    let h = $m.h? | default ""
    let mm = $m.m? | default ""
    if $h == "" and $mm == "" { return null }
    let hours = if $h == "" { 0 } else { $h | into int }
    let minutes = if $mm == "" { 0 } else { $mm | into int }
    let total = $hours * 60 + $minutes
    if $total > 0 { $total } else { null }
}

# 15:00, 9:05: the next time the clock reads it (today, else tomorrow) as seconds since the epoch, null when it is not
# a clock time; ReminderFlowModel.js clockNext reads the same
export def clock-next [text: string]: nothing -> any {
    let m = $text | parse --regex '^(?<h>[01]?\d|2[0-3]):(?<m>[0-5]\d)$' | get --optional 0
    if $m == null { return null }
    let time = $"($m.h | fill -a r -c 0 -w 2):($m.m):00"
    let today = $"(date now | format date '%Y-%m-%d') ($time)" | into datetime --format '%Y-%m-%d %H:%M:%S'
    # tomorrow's date at the same clock time, not 24 h later: a dst change makes that an hour off
    let at = if $today > (date now) { $today } else {
        $"($today + 1day | format date '%Y-%m-%d') ($time)" | into datetime --format '%Y-%m-%d %H:%M:%S'
    }
    $at | into int | $in // 1_000_000_000
}

def --wrapped "main remind" [duration, ...message]: nothing -> nothing {
    let duration = $duration | into string
    let message = $message | each { into string }
    let line = $"! ([$duration ...$message] | str join ' ')"
    let minutes = minutes-of $duration
    let at = clock-next $duration
    if $minutes == null and $at == null {
        capture-fail $BELL_GLYPH "Reminder not set" $"not a duration or time: ($duration) \(90, 10m, 2h, 1h30m, 15:00\)" $line
    }
    let when = if $at != null { [at $at] } else { [$minutes] }
    # one joined argument: reminder.nu's typed words would read a lone true or null as a bool
    let r = ^($HERE | path join reminder.nu) ...$when -- ...([($message | str join " ")] | where $it != "") | complete
    if $r.exit_code != 0 { capture-fail $BELL_GLYPH "Reminder not set" ($r.stderr | str trim | lines | get --optional 0 | default "reminder.nu failed") $line }
}

# one dated heading per day, newest entries at the bottom; nvim and the agents read it as plain markdown
def --wrapped "main note" [...words]: nothing -> nothing {
    let words = $words | each { into string }
    if ($words | is-empty) { error make {msg: "nothing to note"} }
    let text = $words | str join " "
    let inbox = $nu.home-dir | path join $INBOX
    try {
        mkdir ($inbox | path dirname)
        let heading = $"## (date now | format date '%Y-%m-%d')"
        let has_heading = ($inbox | path exists) and (open --raw $inbox | lines | any {|line| $line == $heading })
        let prefix = if $has_heading { "" } else if ($inbox | path exists) { $"\n($heading)\n\n" } else { $"# Inbox\n\n($heading)\n\n" }
        $"($prefix)- (date now | format date '%H:%M') ($text)\n" | save --append $inbox
    } catch {|err|
        capture-fail $NOTE_GLYPH "Not noted" $err.msg $"# ($text)"
    }
    action-notify $NOTE_GLYPH "Noted" $text
}

def main []: nothing -> nothing {
    print "capture task <words> | remind <90|10m|2h|1h30m|15:00> <message> | note <words>"
}

#!/usr/bin/env -S nu --no-config-file
# The homelab calendar, both ways: `push` uploads the pending tasks with a due date as tasks.ics (they appear on the
# TRMNL and in merged.ics), `events` prints today's and tomorrow's events for the quickshell agenda. Both read
# ~/.config/task/calendar.env (CALENDAR_FEED, CALENDAR_UPLOAD) and do nothing without it.

const ENV_FILE = ($nu.home-dir | path join .config task calendar.env)
# the calendar's own copy of the tasks: the agenda lists those from taskwarrior directly
const OWN_SOURCE = "tasks"
const BLOCK = 30min

def endpoints []: nothing -> record {
    if not ($ENV_FILE | path exists) { return {} }
    open --raw $ENV_FILE | lines | where ($it =~ '^[A-Z_]+=') | parse "{key}={value}"
        | reduce --fold {} {|row, acc| $acc | insert $row.key ($row.value | str trim) }
}

def tw-date [raw: string]: nothing -> datetime {
    $raw | str replace 'Z' '+0000' | into datetime --format '%Y%m%dT%H%M%S%z'
}

def ics-escape []: string -> string {
    str replace --all '\' '\\' | str replace --all ';' '\;' | str replace --all ',' '\,' | str replace --all "\n" '\n'
}

def ics-utc [when: datetime]: nothing -> string { $when | date to-timezone UTC | format date '%Y%m%dT%H%M%SZ' }

# Due at local midnight or at eod is a day, not a moment: an all-day event; else a block that ends at due.
def vevent [task: record, stamp: string]: nothing -> list<string> {
    let due = tw-date $task.due | date to-timezone local
    let clock = $due | format date '%H:%M:%S'
    let title = [($task.project? | default "") $task.description] | where ($it | is-not-empty) | str join ": "
    let span = if $clock in ["00:00:00" "23:59:59"] {
        let day = $due | format date '%Y%m%d'
        let next = $due + 1day | format date '%Y%m%d'
        [$"DTSTART;VALUE=DATE:($day)" $"DTEND;VALUE=DATE:($next)"]
    } else {
        [$"DTSTART:(ics-utc ($due - $BLOCK))" $"DTEND:(ics-utc $due)"]
    }
    ["BEGIN:VEVENT" $"UID:($task.uuid)@taskwarrior" $"DTSTAMP:($stamp)" ...$span $"SUMMARY:($title | ics-escape)" "END:VEVENT"]
}

def "main push" [] {
    let url = endpoints | get -o CALENDAR_UPLOAD
    if $url == null { return }
    let tasks = ^task rc.verbose=nothing rc.hooks=off rc.json.array=on status:pending due.any: export | from json
    let stamp = ics-utc (date now)
    let body = [
        "BEGIN:VCALENDAR" "VERSION:2.0" "PRODID:-//arch-dotfiles//task-calendar//EN" "X-WR-CALNAME:Tasks"
        ...($tasks | each {|task| vevent $task $stamp } | flatten)
        "END:VCALENDAR"
    ] | str join "\r\n"
    let file = mktemp --tmpdir task-calendar-XXXXXX.ics
    $"($body)\r\n" | save --force $file
    let result = do { ^curl -sSf --max-time 20 -T $file $"($url | str trim --right --char '/')/($OWN_SOURCE).ics" } | complete
    rm $file
    if $result.exit_code != 0 { error make {msg: $"task-calendar: upload failed: ($result.stderr | str trim)"} }
}

# One list over today and tomorrow, each event tagged with its day, the tasks' own copies left out.
def "main events" [] {
    let feed = endpoints | get -o CALENDAR_FEED
    if $feed == null { print '{"events":[]}'; return }
    let events = ["day.json" "day-next.json"] | each {|name|
        let view = ^curl -sSf --max-time 10 $"($feed | str trim --right --char '/')/($name)" | from json
        $view.day.events | each {|event| $event | insert day $view.weekday | insert today $view.is_today }
    } | flatten | where source != $OWN_SOURCE
    {events: $events} | to json --raw | print
}

def main [] { help main }

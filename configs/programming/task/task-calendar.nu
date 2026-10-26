#!/usr/bin/env -S nu --no-config-file
# Today's and tomorrow's events from the homelab calendar feed, for the agenda; does nothing without
# ~/.config/task/calendar.env.

const ENV_FILE = ($nu.home-dir | path join .config task calendar.env)

def endpoints []: nothing -> record {
    if not ($ENV_FILE | path exists) { return {} }
    open --raw $ENV_FILE | lines | where ($it =~ '^[A-Z_]+=') | parse "{key}={value}"
        | reduce --fold {} {|row, acc| $acc | insert $row.key ($row.value | str trim) }
}

# One list over today and tomorrow, each event tagged with its day.
def "main events" [] {
    let feed = endpoints | get -o CALENDAR_FEED
    if $feed == null { print '{"events":[]}'; return }
    let events = ["day.json" "day-next.json"] | each {|name|
        let view = ^curl -sSf --max-time 10 $"($feed | str trim --right --char '/')/($name)" | from json
        $view.day.events | each {|event| $event | insert day $view.weekday | insert today $view.is_today }
    } | flatten
    {events: $events} | to json --raw | print
}

def main [] { help main }

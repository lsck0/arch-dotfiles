#!/usr/bin/env -S nu --no-config-file
# Agenda events from the homelab calendar; no-op without ~/.config/task/calendar.env.

const ENV_FILE = ($nu.home-dir | path join .config task calendar.env)
# the last good answer, served while the feed is unreachable so the agenda keeps its events
const CACHE_FILE = "task-calendar/events.json"

def endpoints []: nothing -> record {
    if not ($ENV_FILE | path exists) { return {} }
    open --raw $ENV_FILE | lines | where ($it =~ '^[A-Z_]+=') | parse "{key}={value}"
        | reduce --fold {} {|row, acc| $acc | insert $row.key ($row.value | str trim) }
}

# One list over today and tomorrow, each event tagged with its day.
def "main events" [] {
    let feed = endpoints | get -o CALENDAR_FEED
    if $feed == null { print '{"events":[]}'; return }
    let fetched = try {
        ["day.json" "day-next.json"] | each {|name|
            let view = ^curl -sSf --max-time 10 $"($feed | str trim --right --char '/')/($name)" | from json
            $view.day.events | each {|event| $event | insert day $view.weekday | insert today $view.is_today }
        } | flatten
    } catch { null }
    let cache = $env.XDG_CACHE_HOME? | default ($nu.home-dir | path join .cache) | path join $CACHE_FILE
    if $fetched == null {
        if ($cache | path exists) { open --raw $cache | print } else { print '{"events":[]}' }
        return
    }
    let out = {events: $fetched} | to json --raw
    mkdir ($cache | path dirname)
    $out | save --force $cache
    $out | print
}

def main [] { help main }

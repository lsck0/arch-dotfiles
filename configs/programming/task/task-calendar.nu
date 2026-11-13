#!/usr/bin/env -S nu --no-config-file
# Agenda events from the homelab calendar; no-op without ~/.config/task/calendar.env.

const REPO = path self | path expand | path dirname --num-levels 4
use ($REPO | path join scripts lib state.nu) [env-file-load xdg]

const ENV_FILE = ($nu.home-dir | path join .config task calendar.env)
# the last good answer, served while the feed is unreachable so the agenda keeps its events
const CACHE_FILE = "task-calendar/events.json"
# the feed's one-day views, today first; the agenda shows this many days
const VIEWS = ["day.json" "day-next.json" "day-after-next.json"]
const FETCH_TIMEOUT_S = 10

# The cached events still on one of the VIEWS' days, their day and today flag taken from the date, not from the fetch:
# a cache from an earlier day would otherwise show that day's events as today's.
def cached-events [cache: path]: nothing -> list<record> {
    let events = try { open $cache | get events } catch { [] }
    let today = date now | format date "%F"
    let days = 0..<($VIEWS | length) | each {|offset| (date now) + ($offset * 1day) }
        # the feed names days in English, whatever LC_TIME says
        | each {|d| {date: ($d | format date "%F"), weekday: (with-env {LC_ALL: C} { $d | format date "%A" })} }
    $events | each {|event|
        let start = $event.start | str substring 0..9
        let end = $event.end? | default $event.start | str substring 0..9
        # an all-day end is exclusive; a timed event belongs to its start day
        let day = $days | where {|d| if $event.all_day? == true { $start <= $d.date and $d.date < $end } else { $start == $d.date } }
            | get --optional 0
        if $day != null { $event | upsert day $day.weekday | upsert today ($day.date == $today) }
    } | compact
}

# One list over the VIEWS' days, each event tagged with its day.
def "main events" [] {
    let feed = env-file-load $ENV_FILE | get --optional CALENDAR_FEED
    if $feed == null { print '{"events":[]}'; return }
    # a view the feed does not publish (yet) drops out alone; only no view at all falls back to the cache
    let views = $VIEWS | each {|name|
        try { ^curl -sSf --max-time $FETCH_TIMEOUT_S $"($feed | str trim --right --char '/')/($name)" | from json } catch { null }
    } | compact
    let fetched = if ($views | is-empty) { null } else {
        $views | each {|view| $view.day.events | each {|event| $event | insert day $view.weekday | insert today $view.is_today } }
        | flatten
    }
    let cache = xdg cache $CACHE_FILE
    if $fetched == null { {events: (cached-events $cache)} | to json --raw | print; return }
    let out = {events: $fetched} | to json --raw
    mkdir ($cache | path dirname)
    $out | save --force $cache
    $out | print
}

def main [] { help main }

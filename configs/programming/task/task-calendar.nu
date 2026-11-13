#!/usr/bin/env -S nu --no-config-file
# Agenda events from the homelab calendar; no-op without ~/.config/task/calendar.env.

const REPO = path self | path expand | path dirname --num-levels 4
use ($REPO | path join scripts lib state.nu) [env-file-load xdg]

const ENV_FILE = ($nu.home-dir | path join .config task calendar.env)
# the last good answer, served while the feed is unreachable so the agenda keeps its events
const CACHE_FILE = "task-calendar/events.json"
# the feed's one-day views, today first; the agenda shows this many days
const VIEWS = ["day.json" "day-next.json" "day-after-next.json"]
# the feed regenerates every 15 minutes: an answer older than three periods counts as stale
const FEED_STALE_AFTER = 45min
const FETCH_TIMEOUT_S = 10
# an unreachable lab fails the fetch after this instead of FETCH_TIMEOUT_S
const CONNECT_TIMEOUT_S = 3

# The VIEWS' days from today, each with its date and its weekday as the feed names it (English, whatever LC_TIME says).
def view-days []: nothing -> list<record> {
    0..<($VIEWS | length) | each {|offset| (date now) + ($offset * 1day) }
    | each {|d| {date: ($d | format date "%F"), weekday: (with-env {LC_ALL: C} { $d | format date "%A" })} }
}

# A timed event's local start date; the feed gives starts with the source's own offset.
def start-date [event: record]: nothing -> string {
    try { $event.start | into datetime | date to-timezone local | format date "%F" } catch { $event.start | str substring 0..9 }
}

# Whether an event shows on `date`: an all-day one on every day it covers (its end exclusive), a timed one on its start
# day, and on today also while it still runs from an earlier day (a past-midnight party, a trip).
def event-on-day [event: record, date: string, today: string]: nothing -> bool {
    if $event.all_day? == true {
        let start = $event.start | str substring 0..9
        let end = $event.end? | default "" | str substring 0..9
        return ($start == $date or ($start <= $date and $date < $end))
    }
    let start = start-date $event
    let running = $date == $today and $start < $date and (try { ($event.end | into datetime) > (date now) } catch { false })
    $start == $date or $running
}

# One list over `days`, each event on the first day it shows on, tagged with that day; a day's events come from its
# fetched view, else from `fallback` (the cache), so a view that failed keeps the last good answer for its day.
def days-events [days: list<record>, views: list<record>, fallback: list<record>]: nothing -> list<record> {
    let today = date now | format date "%F"
    $days | each {|day|
        let view = $views | where {|v| $v.day?.date? == $day.date } | get --optional 0
        let events = if $view == null { $fallback } else { $view.day.events }
        $events | where {|e| event-on-day $e $day.date $today }
        | each {|e| $e | upsert day $day.weekday | upsert today ($day.date == $today) }
    } | flatten | uniq-by source summary start
}

# One list over the VIEWS' days, each event tagged with its day. `stale` is set when today's events are not the feed's
# fresh answer (the lab unreachable or calendar-sync stopped), `as_of` then says how old they are.
def "main events" [] {
    let feed = env-file-load $ENV_FILE | get --optional CALENDAR_FEED
    if $feed == null { print '{"events":[]}'; return }
    let cache = xdg cache $CACHE_FILE
    let cached = try { open $cache | get events } catch { [] }
    let days = view-days
    let views = $VIEWS | par-each --keep-order {|name|
        let url = $"($feed | str trim --right --char '/')/($name)"
        try { ^curl -sSf --connect-timeout $CONNECT_TIMEOUT_S --max-time $FETCH_TIMEOUT_S $url | from json } catch { null }
    } | compact
    let events = days-events $days $views $cached
    # just past midnight the feed's day.json can still be yesterday: views are matched to days by their own date
    let today_view = $views | where {|v| $v.day?.date? == $days.0.date } | get --optional 0
    if $today_view == null {
        # today's events are the cache's: it stays as it is, so its age stays the age of the last good answer
        let as_of = try { ls $cache | get 0.modified | format date "%+" } catch { null }
        {events: $events, stale: true, as_of: $as_of} | to json --raw | print
        return
    }
    mkdir ($cache | path dirname)
    {events: $events} | to json --raw | save --force $cache
    let generated = try { $today_view.generated_at | into datetime } catch { null }
    let stale = $generated != null and ((date now) - $generated) > $FEED_STALE_AFTER
    {events: $events, stale: $stale, as_of: (if $stale { $today_view.generated_at } else { null })} | to json --raw | print
}

def main [] { help main }

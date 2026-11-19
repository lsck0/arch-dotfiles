#!/usr/bin/env -S nu --no-config-file
# weather.nu alerts: a warning's start and end are unix seconds, so a cached reply served minutes later still names the
# right times; serving it drops the warnings that ended since, and a cached reply from before those fields is a miss
use weather.nu [alerts-current place-current place-key]

const WEATHER = path self weather.nu
const NOW = 1_800_000_000

def fail [msg: string] { error make {msg: $"weather.test: ($msg)"} }

def reply [alerts: list]: nothing -> record { {ok: true, supported: true, alerts: $alerts, countryOthers: 0} }

def main [] {
    let cases = [
        [name alerts want];
        [running [{event: a, startsAt: null, endsAt: ($NOW + 60)}] [a]]
        [open-ended [{event: a, startsAt: null, endsAt: null}] [a]]
        [ended-since [{event: a, startsAt: null, endsAt: $NOW} {event: b, startsAt: null, endsAt: ($NOW + 1)}] [b]]
        [none [] []]
    ]
    for c in $cases {
        let got = reply $c.alerts | alerts-current $NOW | get alerts | get -o event
        if $got != $c.want { fail $"($c.name): ($got | to nuon)" }
    }
    if (reply [{event: a, startsIn: null, endsIn: 5}] | alerts-current $NOW) != null { fail "relative fields served from cache" }

    # a cached place holds only for the cell it was geocoded in, so a move or a pinned location geocodes again
    let berlin = place-key 52.52 13.40
    let place = {address: {country_code: de}, key: $berlin}
    if ($place | place-current (place-key 52.51 13.41)) != $place { fail "same cell missed" }
    if ($place | place-current (place-key 48.20 16.37)) != null { fail "other cell served" }
    if ({address: {country_code: de}} | place-current $berlin) != null { fail "keyless place served" }
    if (null | place-current $berlin) != null { fail "no place served" }
    if not ($berlin =~ '^[0-9a-f]{64}$') { fail $"key is not a hash: ($berlin)" }

    # end to end: a cache hit needs no network, and its times pass through unchanged however old the cache is
    let cache = mktemp -d
    try {
        mkdir ($cache | path join quickshell)
        let file = $cache | path join quickshell weather-alerts.json
        let now = date now | into int | $in // 1_000_000_000
        reply [{event: storm, startsAt: null, endsAt: ($now + 60)} {event: old, startsAt: null, endsAt: ($now - 60)}]
        | to json -r | save $file
        ^touch -d "-5 min" $file
        let got = with-env {XDG_CACHE_HOME: $cache} { ^$nu.current-exe --no-config-file $WEATHER alerts | from json }
        if ($got.alerts | get -o endsAt) != [($now + 60)] { fail $"cache hit: ($got | to nuon)" }
    } catch {|error| rm -rf $cache; error make {msg: $error.msg} }
    rm -rf $cache
}

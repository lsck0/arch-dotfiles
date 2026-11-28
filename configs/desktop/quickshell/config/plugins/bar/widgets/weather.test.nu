#!/usr/bin/env -S nu --no-config-file
# weather.nu alerts: a warning's start and end are unix seconds, so a cached reply served minutes later still names the
# right times; serving it drops the warnings that ended since, and a cached reply from before those fields is a miss
use weather.nu [
    alerts-current area-tokens-map base-current base-for base-ink base-plan place-current place-key radar-bbox radar-extent
    radar-plan-dwd reply-current windy-threshold
]

const WEATHER = path self weather.nu
const NOW = 1_800_000_000

def fail [msg: string] { error make {msg: $"weather.test: ($msg)"} }

def query [url: string]: nothing -> record { $url | url parse | get params | transpose -dr }

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

    # the windy threshold follows the unit open-meteo names in its reply, imperial ("mp/h") included
    for c in [["km/h" 39.0] ["mp/h" 24.2] [null 39.0]] {
        if (windy-threshold $c.0) != $c.1 { fail $"windy threshold for ($c.0): (windy-threshold $c.0)" }
    }

    # a cached place holds only for the cell it was geocoded in, so a move or a pinned location geocodes again
    let berlin = place-key 52.52 13.40
    let place = {address: {country_code: de}, key: $berlin}
    if ($place | place-current (place-key 52.51 13.41)) != $place { fail "same cell missed" }
    if ($place | place-current (place-key 48.20 16.37)) != null { fail "other cell served" }
    if ({address: {country_code: de}} | place-current $berlin) != null { fail "keyless place served" }
    if (null | place-current $berlin) != null { fail "no place served" }
    if not ($berlin =~ '^[0-9a-f]{64}$') { fail $"key is not a hash: ($berlin)" }

    # a radar, field or alerts reply cached for another place, or before the key, is a miss after a move or a pin
    let cached = reply [] | insert key $berlin
    if ($cached | reply-current $berlin) != $cached { fail "same place reply missed" }
    if ($cached | reply-current (place-key 48.20 16.37)) != null { fail "other place reply served" }
    if (reply [] | reply-current $berlin) != null { fail "keyless reply served" }
    if (null | reply-current $berlin) != null { fail "no reply served" }

    # every text keeps its own tokens, a missing address key ("") included wherever it sorts
    for texts in [["Kreis Ansbach" Bayern ""] ["Kreis Ansbach" "" Bayern] [""] []] {
        let map = area-tokens-map $texts
        if ($map | get -o "") != [] { fail $"empty text: ($map | to nuon)" }
        if "Bayern" in $texts and ($map | get -o Bayern) != [bayern] { fail $"shifted tokens: ($map | to nuon)" }
        if "Kreis Ansbach" in $texts and ($map | get -o "Kreis Ansbach") != [ansbach] { fail $"shifted tokens: ($map | to nuon)" }
    }

    # the topography shares the radar's extent and pixel size, so the two align; Bundeslaender borders only in DWD's range
    let half = 512 * 156543.03392 / 128 / 2 | into string --decimals 6
    if (radar-bbox 0.0 0.0) != $"-($half),-($half),($half),($half)" { fail $"bbox at null island: (radar-bbox 0.0 0.0)" }
    let plan = base-plan 52.52 13.40
    let frame = query (radar-plan-dwd 52.52 13.40 | first | get url)
    for part in [relief lines] {
        let q = query ($plan | get $part)
        for field in [bbox srs width height] {
            if ($q | get $field) != ($frame | get $field) { fail $"base ($part) ($field): ($q | get $field)" }
        }
    }
    if (query $plan.relief).transparent != "false" or (query $plan.lines).transparent != "true" { fail "base transparency" }
    if (query $plan.lines).layers != "dwd:Warngebiete_Bundeslaender,dwd:Laender" { fail $"lines in dwd range: ($plan.lines)" }
    if $plan.extent != (radar-extent 52.52 13.40) or $plan.extent == (radar-extent 52.53 13.40) { fail "extent key" }
    if "GeoBasis-DE / BKG" not-in $plan.attribution { fail $"attribution in dwd range: ($plan.attribution)" }
    let lisbon = base-plan 38.72 -9.14
    if (query $lisbon.lines).layers != "dwd:Laender" or "GeoBasis-DE / BKG" in $lisbon.attribution {
        fail $"bundeslaender outside dwd range: ($lisbon | to nuon)"
    }

    let scratch = mktemp -d
    try {
        # the ink: water and lines at their level, flat lowland near none, a shaded slope above it, all white
        let relief = $scratch | path join relief.png
        let lines = $scratch | path join lines.png
        let mask = $scratch | path join mask.png
        ^magick -size 40x40 xc:"rgb(60,140,220)" xc:"rgb(175,200,164)" xc:"rgb(100,110,90)" xc:"rgb(175,200,164)" +append $relief
        ^magick -size 120x40 xc:none -size 40x40 xc:black +append $lines
        if not (base-ink $relief $lines $mask) { fail "ink failed" }
        let alpha = [20 60 100 140] | each {|x| ^magick $mask -format $"%[fx:p{($x),20}.a]" info: | into float }
        let colour = ^magick $mask -format "%[channels] %[fx:minima.r]" info:
        if ($alpha.0 - 0.3 | math abs) > 0.02 or $alpha.1 > 0.1 or $alpha.2 <= $alpha.1 or ($alpha.3 - 0.7 | math abs) > 0.02 {
            fail $"ink levels: ($alpha)"
        }
        if not ($colour starts-with "graya") or not ($colour ends-with " 1") { fail $"ink is not white: ($colour)" }

        # a cached topography holds only for its extent and recipe, while its mask exists
        let file = $scratch | path join base.png
        ^magick -size 1x1 xc:white $file
        let base = {ok: true, file: $file, extent: $plan.extent, recipe: $plan.recipe, attribution: $plan.attribution}
        if ($base | base-current $plan) != $base { fail "same extent base missed" }
        if ($base | base-current $lisbon) != null { fail "other extent base served" }
        if ($base | upsert recipe x | base-current $plan) != null { fail "other recipe base served" }
        if ($base | upsert file ($scratch | path join gone.png) | base-current $plan) != null { fail "base without mask served" }
        if ($base | upsert ok false | base-current $plan) != null or (null | base-current $plan) != null { fail "no base served" }

        # end to end: a cached topography is served without a fetch and left as it is
        mkdir ($scratch | path join quickshell radar)
        let manifest = $scratch | path join quickshell radar base.json
        $base | to json -r | save $manifest
        ^touch -d "-400 days" $manifest
        let before = ls -l $manifest | get 0.modified
        let got = with-env {XDG_CACHE_HOME: $scratch} { base-for 52.52 13.40 }
        if $got != $base or (ls -l $manifest | get 0.modified) != $before { fail $"base cache hit: ($got | to nuon)" }
    } catch {|error| rm -rf $scratch; error make {msg: $error.msg} }
    rm -rf $scratch

    # end to end: a cache hit for the pinned place needs no network, and its times pass through unchanged however old
    # the cache is
    let cache = mktemp -d
    try {
        mkdir ($cache | path join quickshell) ($cache | path join state toggles)
        "52.52,13.40" | save ($cache | path join state toggles weather-location.coords)
        let file = $cache | path join quickshell weather-alerts.json
        let now = date now | into int | $in // 1_000_000_000
        reply [{event: storm, startsAt: null, endsAt: ($now + 60)} {event: old, startsAt: null, endsAt: ($now - 60)}]
        | insert key $berlin | to json -r | save $file
        ^touch -d "-5 min" $file
        let got = with-env {XDG_CACHE_HOME: $cache, XDG_STATE_HOME: ($cache | path join state)} {
            ^$nu.current-exe --no-config-file $WEATHER alerts | from json
        }
        if ($got.alerts | get -o endsAt) != [($now + 60)] { fail $"cache hit: ($got | to nuon)" }
    } catch {|error| rm -rf $cache; error make {msg: $error.msg} }
    rm -rf $cache
}

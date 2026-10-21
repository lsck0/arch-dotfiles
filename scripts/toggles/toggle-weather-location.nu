#!/usr/bin/env -S nu --no-config-file
# The one location every weather script shares: a manual pin, else geoclue, the timezone's coordinate, then ip geo.

use lib.nu [switch-run state-file notify]

const AUTO_CACHE_MAX_AGE = 30min
const GEOCLUE_DEMO = "/usr/lib/geoclue-2.0/demos/where-am-i"
const GEOCLUE_AGENT = "/usr/lib/geoclue-2.0/demos/agent"
const GEOCLUE_TIMEOUT_S = 8
const ZONE_TABS = ["/usr/share/zoneinfo/zone1970.tab" "/usr/share/zoneinfo/zone.tab"]
const IPGEO_URL = "https://ipapi.co/json/"
const IPGEO_TIMEOUT = 6sec
const COORD_DECIMALS = 2

def manual-file []: nothing -> path { state-file weather-location.coords }

def manual-coords []: nothing -> any { try { open --raw (manual-file) | str trim | if ($in | is-empty) { null } else { $in } } }

def coords-format [lat: float, lon: float]: nothing -> string {
    $"($lat | into string --decimals $COORD_DECIMALS),($lon | into string --decimals $COORD_DECIMALS)"
}

def geoclue-coords []: nothing -> any {
    if not ($GEOCLUE_DEMO | path exists) or not ($GEOCLUE_AGENT | path exists) { return null }
    let agent = job spawn { ^$GEOCLUE_AGENT o+e> /dev/null }
    let output = ^timeout $GEOCLUE_TIMEOUT_S $GEOCLUE_DEMO -a 4 -t 6 | complete | get stdout
    job kill $agent
    let found = $output | parse --regex 'Latitude:\s*(?<lat>-?[0-9.]+)[\s\S]*?Longitude:\s*(?<lon>-?[0-9.]+)' | get 0?
    if $found != null { coords-format ($found.lat | into float) ($found.lon | into float) }
}

def timezone-coords []: nothing -> any {
    let zone = ^timedatectl show -p Timezone --value | complete | get stdout | str trim
    let coord = $ZONE_TABS | where ($it | path exists) | each {|tab|
        open --raw $tab | lines | where not ($it starts-with "#") | split column "\t" code coord zones
            | where ($it.zones | split row "," | any { $in == $zone }) | get coord.0?
    } | compact | get 0?
    let parts = $coord | default "" | parse --regex '^(?<lat>[+-]\d{2})(?<lat_min>\d{2})(?<lat_sec>\d{2})?(?<lon>[+-]\d{3})(?<lon_min>\d{2})(?<lon_sec>\d{2})?$' | get 0?
    if $parts == null { return null }
    let degrees = {|deg, min, sec|
        let magnitude = ($deg | into int | math abs) + ($min | into int) / 60 + ($sec | default "0" | into int) / 3600
        if ($deg starts-with "-") { 0 - $magnitude } else { $magnitude }
    }
    coords-format (do $degrees $parts.lat $parts.lat_min $parts.lat_sec) (do $degrees $parts.lon $parts.lon_min $parts.lon_sec)
}

def ipgeo-coords []: nothing -> any {
    let reply = try { http get --max-time $IPGEO_TIMEOUT $IPGEO_URL } catch { {} }
    if $reply.latitude? != null and $reply.longitude? != null { coords-format $reply.latitude $reply.longitude }
}

def resolve []: nothing -> string {
    if (manual-coords) != null { return $"manual (manual-coords)" }
    let cache = state-file weather-location.auto --volatile
    if ($cache | path exists) and ((date now) - (ls $cache | get 0.modified)) < $AUTO_CACHE_MAX_AGE {
        return (open --raw $cache | str trim)
    }
    for source in [geoclue timezone ipgeo] {
        let coords = match $source { geoclue => (geoclue-coords), timezone => (timezone-coords), ipgeo => (ipgeo-coords) }
        if $coords != null {
            $"($source) ($coords)" | save --force $cache
            return $"($source) ($coords)"
        }
    }
    "none"
}

def --wrapped "main set" [...coords: string] {
    let parts = if ($coords | length) == 1 { $coords.0 | split row "," } else { $coords | first 2 }
    if ($parts | length) != 2 or ($parts | any { $in !~ '^[+-]?([0-9]+([.][0-9]*)?|[.][0-9]+)$' }) {
        error make {msg: "usage: toggle-weather-location.nu set <lat> <lon> (decimal degrees)"}
    }
    let lat = $parts.0 | into float
    let lon = $parts.1 | into float
    if ($lat | math abs) > 90 or ($lon | math abs) > 180 {
        error make {msg: "lat must be in [-90, 90], lon in [-180, 180]"}
    }
    let coords = coords-format $lat $lon
    $coords | save --force (manual-file)
    notify "Weather location" "Set manually"
    $coords
}

def "main clear" [] {
    rm --force (manual-file)
    notify "Weather location" "Back to automatic"
}

def "main resolve" [] { resolve }
def "main coords" [] { resolve | split row " " | get 1? | default "" }
def "main source" [] { resolve | split row " " | get 0 }

def main [action: string = "toggle"] {
    switch-run {
        label: "Weather location (manual)"
        is-on: {|| manual-coords | is-not-empty }
        on: {||
            if (manual-coords) != null { return }
            let coords = resolve | split row " " | get 1?
            if $coords == null {
                error make {msg: "no location could be resolved to pin; use: toggle-weather-location.nu set <lat> <lon>"}
            }
            $coords | save --force (manual-file)
        }
        off: {|| rm --force (manual-file) }
    } $action
}

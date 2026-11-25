#!/usr/bin/env -S nu --no-config-file

# clock_zones in mod.nu, through prefs.json; a missing file keeps these
const ZONES_DEFAULT = [
    "NA West=America/Los_Angeles" "NA Central=America/Chicago" "NA East=America/New_York" "UK=Europe/London"
    "Central EU=Europe/Berlin" "NZ=Pacific/Auckland" "JP=Asia/Tokyo"
]
const PREFS = ($nu.home-dir | path join .config quickshell prefs.json)
const WINDOW_H = 25
const STEP_S = 3600

def offset-at [unix_s: int, iana: string]: nothing -> int {
    let z = $unix_s * 1_000_000_000 | into datetime | date to-timezone $iana | format date "%z"
        | parse -r '(?<sign>[+-])(?<h>\d\d)(?<m>\d\d)' | first
    let seconds = ($z.h | into int) * 3600 + ($z.m | into int) * 60
    if $z.sign == "-" { 0 - $seconds } else { $seconds }
}

# "label=Area/City" or a bare zone, labelled by its city; an unknown zone is left out
export def zones-parse [entries: list<string>]: nothing -> table<zone: string, iana: string> {
    $entries | each {|entry|
        let parts = $entry | split row "=" | each { str trim }
        let iana = $parts | last
        let label = if ($parts | length) > 1 { $parts | first } else { $iana | split row "/" | last | str replace --all "_" " " }
        let known = try { date now | date to-timezone $iana | ignore; true } catch { false }
        if $known and $iana != "" { {zone: $label, iana: $iana} }
    } | compact
}

def zones-load []: nothing -> list<string> {
    let zones = try { open $PREFS | get --optional clockZones } catch { null }
    if ($zones | describe) =~ '^list' { $zones | each { into string } } else { $ZONES_DEFAULT }
}

def main [] {
    let start = ((date now | into int) // 1_000_000_000 // $STEP_S - $WINDOW_H) * $STEP_S
    zones-parse (zones-load) | each {|z|
        let samples = 0..(2 * $WINDOW_H) | each {|i|
            let at = $start + $i * $STEP_S
            {fromMs: ($at * 1000), offsetSec: (offset-at $at $z.iana)}
        }
        let spans = $samples | enumerate | where {|s|
            $s.index == 0 or $s.item.offsetSec != ($samples | get ($s.index - 1) | get offsetSec)
        } | get item
        {zone: $z.zone, spans: $spans}
    } | to json -r | print
}

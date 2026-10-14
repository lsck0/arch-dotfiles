#!/usr/bin/env -S nu --no-config-file

const ZONES = [
    [zone iana];
    ["Central Europe" Europe/Berlin]
    [UK Europe/London]
    ["USA East" America/New_York]
    ["USA Central" America/Chicago]
    ["USA West" America/Los_Angeles]
    ["New Zealand" Pacific/Auckland]
]

def main [] {
    let now = date now
    $ZONES | each {|z|
        let offset = $now | date to-timezone $z.iana | format date "%z" | parse -r '(?<sign>[+-])(?<h>\d\d)(?<m>\d\d)' | first
        let seconds = ($offset.h | into int) * 3600 + ($offset.m | into int) * 60
        {zone: $z.zone, offsetSec: (if $offset.sign == "-" { -1 * $seconds } else { $seconds })}
    } | to json -r | print
}

#!/usr/bin/env -S nu --no-config-file
# wayland-boomer over every monitor; no_warps while mapping, else the monitor-0 window rule yanks the cursor

const MAP_TRIES = 60
const MAP_POLL = 50ms
const FOCUS_SETTLE = 100ms

def warps-set [value: bool]: nothing -> nothing {
    ^hyprctl eval $"hl.config\({ cursor = { no_warps = ($value) } }\)" | ignore
}

def main [] {
    let warps_off = ^hyprctl -j getoption cursor:no_warps | from json | get bool
    warps-set true
    # every real monitor, not an agent's headless output: grim alone spans those too and renders at its higher scale
    let monitors = ^hyprctl -j monitors | from json | where name !~ '^HEADLESS-'
    let scale = $monitors | where focused | get -o 0.scale | default ($monitors | get 0.scale)
    let x = $monitors | get x | math min
    let y = $monitors | get y | math min
    let w = $monitors | each { $in.x + $in.width / $in.scale } | math max | $in - $x | math round
    let h = $monitors | each { $in.y + $in.height / $in.scale } | math max | $in - $y | math round
    let geometry = $"($x),($y) ($w)x($h)"
    job spawn {
        try { ^grim -g $geometry -t ppm - | ^wayland-boomer --monitor-scaling ($scale | into string) }
        "done" | job send 0
    } | ignore
    for _ in 1..$MAP_TRIES {
        if (^hyprctl -j clients | from json | any { $in.title == "wayland-boomer" }) { break }
        sleep $MAP_POLL
    }
    sleep $FOCUS_SETTLE
    warps-set $warps_off
    job recv | ignore
}

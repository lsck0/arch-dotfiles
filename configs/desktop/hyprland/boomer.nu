#!/usr/bin/env -S nu --no-config-file
# no_warps while mapping: the monitor-0 window rule would yank the cursor

const MAP_TRIES = 60
const MAP_POLL = 50ms
# focus settles a frame after the map
const FOCUS_SETTLE = 100ms

def warps-set [value: bool]: nothing -> nothing {
    ^hyprctl eval $"hl.config\({ cursor = { no_warps = ($value) } }\)" | ignore
}

def main [] {
    let warps_off = ^hyprctl -j getoption cursor:no_warps | from json | get bool
    warps-set true
    let scale = ^hyprctl -j monitors | from json | where focused | get 0.scale
    job spawn { try { ^grim -t ppm - | ^wayland-boomer --monitor-scaling ($scale | into string) }; "done" | job send 0 } | ignore
    for _ in 1..$MAP_TRIES {
        if (^hyprctl -j clients | from json | any { $in.title == "wayland-boomer" }) { break }
        sleep $MAP_POLL
    }
    sleep $FOCUS_SETTLE
    warps-set $warps_off
    job recv | ignore
}

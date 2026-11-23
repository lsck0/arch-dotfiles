#!/usr/bin/env -S nu --no-config-file
# toggle-monitor-scale.nu's layout arithmetic: mode strings, logical sizes under scale and transform, placing one
# monitor beside another, shifting the layout back to the origin, and merging changes into the saved monitors.
use toggle-monitor-scale.nu [mode-normalize monitor-logical-size position-relative positions-normalize monitors-merge]
use std/assert

const UHD = {name: DP-1, width: 3840, height: 2160, scale: 1.6666666, transform: 0, x: 0, y: 0}
const FHD = {name: HDMI-A-1, width: 1920, height: 1080, scale: 1.0, transform: 0, x: 2304, y: 0}

def mode-cases []: nothing -> nothing {
    assert equal (mode-normalize "3840x2160@144.00Hz") "3840x2160@144"
    assert equal (mode-normalize "1920x1080@59.94Hz") "1920x1080@59.94"
    assert equal (mode-normalize "800x600@60.32") "800x600@60.32"
    assert equal (mode-normalize "3840x2160@144.00000") "3840x2160@144"
    assert equal (mode-normalize "1280x720@120.50Hz") "1280x720@120.5"
    assert equal (mode-normalize "3840x2160@144") "3840x2160@144"
    assert error { mode-normalize highrr }
}

def size-cases []: nothing -> nothing {
    assert equal (monitor-logical-size $UHD) {width: 2304, height: 1296}
    assert equal (monitor-logical-size ($FHD | merge {transform: 1})) {width: 1080, height: 1920}
    assert equal (monitor-logical-size ($FHD | merge {transform: 2})) {width: 1920, height: 1080}
    assert equal (monitor-logical-size ($FHD | merge {transform: 7})) {width: 1080, height: 1920}
}

def relation-cases []: nothing -> nothing {
    assert equal (position-relative $FHD $UHD right-of) {x: 2304, y: 0}
    assert equal (position-relative $FHD $UHD left-of) {x: -1920, y: 0}
    assert equal (position-relative $FHD $UHD above) {x: 0, y: -1080}
    assert equal (position-relative $FHD $UHD below) {x: 0, y: 1296}
    assert error { position-relative $FHD $UHD beside }
}

def normalize-cases []: nothing -> nothing {
    let placed = [{name: DP-1, x: 0, y: 0} {name: HDMI-A-1, x: -1920, y: -1080}]
    assert equal (positions-normalize $placed) [{name: DP-1, x: 1920, y: 1080} {name: HDMI-A-1, x: 0, y: 0}]
    assert equal (positions-normalize [{name: DP-1, x: 0, y: 0}]) [{name: DP-1, x: 0, y: 0}]
    assert equal (positions-normalize []) []
}

def merge-cases []: nothing -> nothing {
    let saved = [{output: DP-1, mode: "3840x2160@144", position: "0x0", scale: 1.666667}]
    let live = [($UHD | merge {refreshRate: 144.0}) ($FHD | merge {refreshRate: 60.0})]
    let mode = monitors-merge $saved $live [{output: DP-1, mode: "1920x1080@120", scale: 1.0}]
    assert equal $mode [{output: DP-1, mode: "1920x1080@120", position: "0x0", scale: 1.0}]
    let seeded = monitors-merge $saved $live [{output: HDMI-A-1, position: "0x1296"}]
    assert equal ($seeded | get output) [DP-1 HDMI-A-1]
    assert equal ($seeded | last) {output: HDMI-A-1, mode: "1920x1080@60.00000", position: "0x1296", scale: 1.0}
    let both = monitors-merge $saved $live [{output: HDMI-A-1, position: "0x0"} {output: DP-1, position: "1920x0"}]
    assert equal ($both | get position) ["1920x0" "0x0"]
}

def main [] {
    mode-cases
    size-cases
    relation-cases
    normalize-cases
    merge-cases
    print "monitor layout: ok"
}

#!/usr/bin/env -S nu --no-config-file
# Every theme through pywalfox's own derivation (its dark and light templates, from the slots pywalfox-slots writes):
# text holds 4.5:1 on the frame, the toolbar and popups, and the url bar, the highlight 3:1 against its text.

use mod.nu [pywalfox-slots pywalfox-brighten]
use ../../core/wallust/palette.nu [hex-to-rgb contrast]

const THEMES = path self ../../../themes
const TEXT = 4.5
const HIGHLIGHT = 3.0
const WHITE = [1.0 1.0 1.0]

def surfaces [theme: record]: nothing -> list<record> {
    let slots = pywalfox-slots $theme.special.background $theme.special.foreground $theme.colors.color4 $theme.colors.color5
    let c = $theme.colors | merge $slots
    let c0 = $c.color0 | hex-to-rgb
    # the light slots set color7, the frame's source; the dark ones leave it
    if "color7" in $slots {
        let text = $c0 | pywalfox-brighten 1.25
        let frame = $c.color7 | hex-to-rgb | pywalfox-brighten 0.1 205 220
        [
            [what a b want];
            ["text on frame" $text $frame $TEXT]
            ["text on toolbar, popup, url bar" $text $WHITE $TEXT]
            ["highlight" $WHITE ($c.color3 | hex-to-rgb) $HIGHLIGHT]
        ]
    } else {
        let text = $c.color15 | hex-to-rgb
        [
            [what a b want];
            ["text on frame" $text $c0 $TEXT]
            ["text on toolbar and popup" $text ($c0 | pywalfox-brighten 1.25) $TEXT]
            ["text on url bar" $text ($c0 | pywalfox-brighten 1.85) $TEXT]
            ["highlight" $c0 ($c.color10 | hex-to-rgb) $HIGHLIGHT]
        ]
    }
}

def main [] {
    let failed = glob ($THEMES | path join *.json) | sort | each {|f|
        surfaces (open $f) | where {|s| (contrast $s.a $s.b) < $s.want }
        | each {|s| $"($f | path basename): ($s.what) ((contrast $s.a $s.b) | math round --precision 2):1" }
    } | flatten
    for line in $failed { print --stderr $"firefox.test: ($line)" }
    if ($failed | is-not-empty) { error make {msg: $"firefox.test: ($failed | length) surfaces below their contrast"} }
}

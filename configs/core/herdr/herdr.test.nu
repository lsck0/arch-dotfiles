#!/usr/bin/env -S nu --no-config-file
# theme-custom under every theme: the colours herdr draws text in keep their floor on the selection, the surface
# nearest the foreground that text sits on.

use mod.nu [theme-custom]
use ../wallust/scripts/palette.nu [ACCENT_RATIO TEXT_RATIO condition-bg hex-to-rgb is-light passes rgb-to-hex]

const THEMES = path self ../../../themes
const FLOORS = {overlay0: $ACCENT_RATIO, overlay1: $TEXT_RATIO, subtext0: $TEXT_RATIO}

# A theme as `palette-load` reads it once wallust applied it.
def palette-of [spec: record]: nothing -> record {
    let bg = $spec.special.background | hex-to-rgb
    let colors = 0..15 | each {|i| [$"c($i)" ($spec.colors | get $"color($i)")] } | into record
    {bg: $spec.special.background, fg: $spec.special.foreground, ...$colors}
        | merge {light: (if ($bg | is-light) { "1" } else { "0" }), bg_conditioned: ($bg | condition-bg | rgb-to-hex --prefix "#")}
}

def main [] {
    let problems = glob ($THEMES | path join "*.json") | sort | each {|file|
        let name = $file | path parse | get stem
        let s = theme-custom (palette-of (open $file)) | into record
        let surface = $s.selection_bg | hex-to-rgb
        $FLOORS | items {|slot, ratio|
            let hex = $s | get $slot
            if not (passes ($hex | hex-to-rgb) $surface $ratio) {
                $"($name): ($slot) ($hex) below ($ratio):1 on selection_bg ($s.selection_bg)"
            }
        } | compact
    } | flatten
    if ($problems | is-not-empty) { error make {msg: ($problems | str join "\n")} }
}

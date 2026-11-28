#!/usr/bin/env -S nu --no-config-file
# theme-custom under every theme: the colours herdr draws text in keep their floor on the selection, the surface
# nearest the foreground that text sits on.

use mod.nu [TEXT_FLOORS theme-custom]
use ../wallust/scripts/palette.nu [hex-to-rgb palette-from-wal passes]

const THEMES = path self ../../../themes

def main [] {
    let problems = glob ($THEMES | path join "*.json") | sort | each {|file|
        let name = $file | path parse | get stem
        let s = theme-custom (open $file | palette-from-wal) | into record
        let surface = $s.selection_bg | hex-to-rgb
        $TEXT_FLOORS | items {|slot, ratio|
            let hex = $s | get $slot
            if not (passes ($hex | hex-to-rgb) $surface $ratio) {
                $"($name): ($slot) ($hex) below ($ratio):1 on selection_bg ($s.selection_bg)"
            }
        } | compact
    } | flatten
    if ($problems | is-not-empty) { error make {msg: ($problems | str join "\n")} }
}

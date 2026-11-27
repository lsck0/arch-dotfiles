#!/usr/bin/env -S nu --no-config-file
# faint-opacity under every theme: faint text, the foreground at that opacity, keeps the dim-text floor on the
# background.

use mod.nu [faint-opacity]
use ../../core/wallust/scripts/palette.nu [ACCENT_RATIO hex-to-rgb mix passes]

const THEMES = path self ../../../themes

def main [] {
    let problems = glob ($THEMES | path join "*.json") | sort | each {|file|
        let spec = open $file
        let a = faint-opacity {bg: $spec.special.background, fg: $spec.special.foreground}
        let bg = $spec.special.background | hex-to-rgb
        if not (passes (mix $bg ($spec.special.foreground | hex-to-rgb) $a) $bg $ACCENT_RATIO) {
            $"($file | path parse | get stem): faint text at ($a) below ($ACCENT_RATIO):1"
        }
    } | compact
    if ($problems | is-not-empty) { error make {msg: ($problems | str join "\n")} }
}

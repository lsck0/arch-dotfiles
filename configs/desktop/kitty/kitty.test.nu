#!/usr/bin/env -S nu --no-config-file
# dim_opacity under every theme: dim text, the foreground at that opacity, keeps the dim-text floor on the background.

use mod.nu [dim-opacity]
use ../../core/wallust/scripts/palette.nu [ACCENT_RATIO hex-to-rgb mix passes]

const THEMES = path self ../../../themes

def main [] {
    let problems = glob ($THEMES | path join "*.json") | sort | each {|file|
        let spec = open $file
        let a = dim-opacity {bg: $spec.special.background, fg: $spec.special.foreground}
        let bg = $spec.special.background | hex-to-rgb
        if not (passes (mix $bg ($spec.special.foreground | hex-to-rgb) $a) $bg $ACCENT_RATIO) {
            $"($file | path parse | get stem): dim text at ($a) below ($ACCENT_RATIO):1"
        }
    } | compact
    if ($problems | is-not-empty) { error make {msg: ($problems | str join "\n")} }
}

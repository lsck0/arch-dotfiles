#!/usr/bin/env -S nu --no-config-file
use ../configs/core/wallust/palette.nu [hex-to-rgb is-light passes TEXT_RATIO]

const THEMES = path self .
const ACCENT_RATIO = 3.0
const TEXT_SLOTS = [color4 color12]
const ACCENT_SLOTS = [color1 color2 color3 color5 color6 color8 color9 color10 color11 color13 color14]
const DARK_TEXT_SLOTS = [color7 color15]

def contrast-problems [name: string, spec: record]: nothing -> list<string> {
    let bg = $spec.special.background | hex-to-rgb
    let text_ratio = [foreground ...$TEXT_SLOTS ...(if ($bg | is-light) { [] } else { $DARK_TEXT_SLOTS })]
        | each {|s| {slot: $s, ratio: $TEXT_RATIO} }
    let rules = $text_ratio | append ($ACCENT_SLOTS | each {|s| {slot: $s, ratio: $ACCENT_RATIO} })
    $rules | each {|r|
        let hex = if $r.slot == foreground { $spec.special.foreground } else { $spec.colors | get $r.slot }
        if not (passes ($hex | hex-to-rgb) $bg $r.ratio) { $"($name): ($r.slot) ($hex) below ($r.ratio):1 on ($spec.special.background)" }
    } | compact
}

def main [] {
    let themes = glob ($THEMES | path join "*.json") | each {|file|
        let spec = open $file
        {name: ($file | path parse | get stem), pair: $spec.pair?, light: ($spec.special.background | hex-to-rgb | is-light)}
    }
    let contrast = glob ($THEMES | path join "*.json") | each {|file| contrast-problems ($file | path parse | get stem) (open $file) } | flatten
    let problems = $contrast ++ ($themes | each {|t|
        let partner = $themes | where name == $t.pair | get --optional 0
        if $t.pair == null {
            $"($t.name): no pair"
        } else if $partner == null {
            $"($t.name): pair ($t.pair) is no theme"
        } else if $partner.light == $t.light {
            $"($t.name): pair ($t.pair) is the same mode"
        } else if $t.light and $partner.pair != $t.name {
            $"($t.name): pair ($t.pair) pairs with ($partner.pair) instead"
        }
    } | compact)
    if ($problems | is-not-empty) {
        print -e ($problems | str join "\n")
        exit 1
    }
    print "themes.test: ok"
}

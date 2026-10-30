#!/usr/bin/env -S nu --no-config-file
use ../configs/core/wallust/palette.nu [hex-to-rgb is-light passes TEXT_RATIO]

const THEMES = path self .
const WALLPAPERS = path self ../wallpapers
const ACCENT_RATIO = 3.0
const TEXT_SLOTS = [color4 color12]
const ACCENT_SLOTS = [color1 color2 color3 color5 color6 color8 color9 color10 color11 color13 color14]
const DARK_TEXT_SLOTS = [color7 color15]
const SPECIAL_SLOTS = [background foreground cursor]
const COLOR_SLOTS = [
    color0 color1 color2 color3 color4 color5 color6 color7
    color8 color9 color10 color11 color12 color13 color14 color15
]
const HEX_COLOR = '^#[0-9a-fA-F]{6}$'

def hex-color [value: any]: nothing -> bool { ($value | describe) == "string" and ($value =~ $HEX_COLOR) }

# Every key the contrast checks and the wallpaper contract read, so a malformed theme is a problem, not a crash.
def schema-problems [name: string, spec: record]: nothing -> list<string> {
    let special = $spec.special? | default {}
    let colors = $spec.colors? | default {}
    let bad_special = $SPECIAL_SLOTS | each {|s|
        let v = $special | get --optional $s
        if not (hex-color $v) { $"($name): special.($s) ($v) is not a #rrggbb color" }
    }
    let bad_colors = $COLOR_SLOTS | each {|s|
        let v = $colors | get --optional $s
        if not (hex-color $v) { $"($name): colors.($s) ($v) is not a #rrggbb color" }
    }
    [...$bad_special ...$bad_colors] | compact
}

def contrast-problems [name: string, spec: record]: nothing -> list<string> {
    let bg = $spec.special.background | hex-to-rgb
    let text_rules = [foreground ...$TEXT_SLOTS ...(if ($bg | is-light) { [] } else { $DARK_TEXT_SLOTS })]
        | each {|s| {slot: $s, ratio: $TEXT_RATIO} }
    let rules = $text_rules | append ($ACCENT_SLOTS | each {|s| {slot: $s, ratio: $ACCENT_RATIO} })
    $rules | each {|r|
        let hex = if $r.slot == foreground { $spec.special.foreground } else { $spec.colors | get $r.slot }
        if not (passes ($hex | hex-to-rgb) $bg $r.ratio) { $"($name): ($r.slot) ($hex) below ($r.ratio):1 on ($spec.special.background)" }
    } | compact
}

# Each theme's wallpaper has a public copy in wallpapers/, and no two themes share one (wallpaper.nu picks the first).
def wallpaper-problems [themes: list<record>]: nothing -> list<string> {
    let missing = $themes | each {|t|
        let w = $t.spec.wallpaper?
        if ($w | describe) != "string" or ($w | is-empty) {
            $"($t.name): no wallpaper"
        } else if not ($WALLPAPERS | path join $w | path exists) {
            $"($t.name): wallpaper ($w) not in wallpapers/"
        }
    } | compact
    let dups = $themes | where {|t| ($t.spec.wallpaper? | describe) == "string" }
        | group-by {|t| $t.spec.wallpaper } | items {|w, g|
            if ($g | length) > 1 { $"wallpaper ($w) used by ($g | get name | str join ', ')" }
        } | compact
    [...$missing ...$dups]
}

def main [] {
    let themes = glob ($THEMES | path join "*.json") | each {|file|
        {name: ($file | path parse | get stem), spec: (open $file)}
    } | insert schema {|t| schema-problems $t.name $t.spec }
    let schema = $themes | get schema | flatten
    let wallpaper = wallpaper-problems $themes
    # contrast and pair read the color slots, so only themes with an intact schema are checked for them
    let good = $themes | where {|t| $t.schema | is-empty }
    let paired = $good | each {|t|
        {name: $t.name, pair: $t.spec.pair?, light: ($t.spec.special.background | hex-to-rgb | is-light)}
    }
    let contrast = $good | each {|t| contrast-problems $t.name $t.spec } | flatten
    let pairs = $paired | each {|t|
        let partner = $paired | where name == $t.pair | get --optional 0
        if $t.pair == null {
            $"($t.name): no pair"
        } else if $partner == null {
            $"($t.name): pair ($t.pair) is no theme"
        } else if $partner.light == $t.light {
            $"($t.name): pair ($t.pair) is the same mode"
        } else if $t.light and $partner.pair != $t.name {
            $"($t.name): pair ($t.pair) pairs with ($partner.pair) instead"
        }
    } | compact
    let problems = [...$schema ...$wallpaper ...$contrast ...$pairs]
    if ($problems | is-not-empty) {
        print -e ($problems | str join "\n")
        exit 1
    }
    print "themes.test: ok"
}

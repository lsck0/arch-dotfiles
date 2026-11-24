#!/usr/bin/env -S nu --no-config-file
# palette-load and palette-rgb on a missing, a malformed and a slot-broken colors.json degrade to null; a theme loads.
# A derived palette comes out of condition-derived with color0 the background, color8 a grey, every floor of
# contrast-floors kept, and color4 on a hue the picture has.

use scripts/palette.nu [condition-derived contrast-floors hex-to-rgb hue-apart is-light palette-load palette-rgb passes rgb-to-hsv]

const THEME = path self ../../../themes/atuel-light.json
# what wallust derived from a night picture, blue but for a few lamps: a navy color0, a brown color8, a brown color4
const NIGHT = {
    special: {background: "#0B1116", foreground: "#E8C19C", cursor: "#9CA59D"}
    colors: {
        color0: "#000F29", color1: "#7B7E83", color2: "#768081", color3: "#736B64"
        color4: "#8B796A", color5: "#50899D", color6: "#A38160", color7: "#D7B18D"
        color8: "#957454", color9: "#7B7E83", color10: "#768081", color11: "#736B64"
        color12: "#8B796A", color13: "#50899D", color14: "#A38160", color15: "#E3CFBE"
    }
}
const BLUE = [{rgb: [0.1 0.3 0.5], count: 4000} {rgb: [0.2 0.2 0.2], count: 96}]
const WARM = [{rgb: [0.6 0.4 0.2], count: 4096}]
const GREY = [{rgb: [0.3 0.3 0.3], count: 4096}]
# color8's saturation stays below this: the background's hue, thinned by the walk to white or black
const GREY_SATURATION_MAX = 0.2
const HUE_SAME_DEG = 3.0

# What is wrong with a conditioned palette; accent is the slot of the input whose hue color4 must have.
def derived-problems [wal: record, picture: table, accent: int]: nothing -> list<string> {
    let out = $wal | condition-derived $picture
    let bg = $out.special.background | hex-to-rgb
    let slot = {|palette, name| if $name == foreground { $palette.special.foreground } else { $palette.colors | get $name } | hex-to-rgb }
    let low = contrast-floors ($bg | is-light) | where {|f| not (passes (do $slot $out $f.slot) $bg $f.ratio) } | get slot
    [
        (if $out.special.background != $wal.special.background { "background changed" })
        (if $out.colors.color0 != $out.special.background { "color0 is not the background" })
        (if (do $slot $out color8 | rgb-to-hsv).1 > $GREY_SATURATION_MAX { "color8 is no grey" })
        (if ($low | is-not-empty) { $"below the floor: ($low | str join ' ')" })
        (if (hue-apart (do $slot $out color4) (do $slot $wal $"color($accent)")) > $HUE_SAME_DEG { $"color4 is not on color($accent)'s hue" })
        (if (hue-apart (do $slot $out color12) (do $slot $wal $"color($accent + 8)")) > $HUE_SAME_DEG { $"color12 is not on color($accent + 8)'s hue" })
        (if ($out | condition-derived $picture) != $out { "a second pass changes it" })
    ] | compact
}

def main [] {
    let theme = open $THEME
    let cases = [
        [name content load];
        [missing null false]
        [malformed "{not json" false]
        [slot-not-hex ($theme | update colors.color3 zzz | to json) false]
        [theme ($theme | to json) true]
    ]
    let dir = mktemp --directory
    let failed = $cases | where {|c|
        let cache = $dir | path join $c.name
        mkdir ($cache | path join wal)
        if $c.content != null { $c.content | save ($cache | path join wal colors.json) }
        with-env {XDG_CACHE_HOME: $cache} {
            let p = palette-load
            let rgb = palette-rgb palette.test
            if $c.load { $p == null or $rgb == null or $p.light != "1" } else { $p != null or $rgb != null }
        }
    } | get name
    rm --recursive $dir
    if ($failed | is-not-empty) { error make {msg: $"palette.test: wrong result for ($failed | str join ', ')"} }
    let dim = $NIGHT | update colors.color4 "#473D60" | update colors.color12 "#473D60" | update colors.color7 "#5A5A5A"
        | update special.foreground "#707070"
    let derived = [
        [name wal picture accent];
        [foreign-accent-trades-with-the-pictures-hue $NIGHT $BLUE 5]
        [accent-the-picture-has-is-kept $NIGHT $WARM 4]
        [picture-without-chroma-keeps-it $NIGHT $GREY 4]
        [unreadable-picture-keeps-it $NIGHT [] 4]
        [dim-slots-reach-their-floors $dim $WARM 6]
        [light-background ($theme | select special colors) [] 4]
    ]
    let wrong = $derived | each {|c| derived-problems $c.wal $c.picture $c.accent | each {|p| $"($c.name): ($p)" } } | flatten
    if ($wrong | is-not-empty) { error make {msg: $"palette.test: condition-derived: ($wrong | str join '; ')"} }
}

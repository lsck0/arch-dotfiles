#!/usr/bin/env -S nu --no-config-file
# palette-load and palette-rgb on a missing, a malformed and a slot-broken colors.json degrade to null; a theme loads.
# blend-floor finds the lowest passing blend and null when the foreground itself falls short.
# A derived palette comes out of condition-derived with color0 the background, color8 a grey, every floor of
# contrast-floors kept, and color4 on a hue the picture has.

use scripts/palette.nu [blend-floor condition-derived contrast-floors hex-to-rgb hue-apart is-light mix palette-load palette-rgb passes rgb-to-hsv]

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
# a floor the theme's foreground reaches well above 0 (kitty's dim text)
const BLEND_FROM = 0.1
const BLEND_STEP = 0.05
const BLEND_RATIO = 3.0

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
    let bg = $theme.special.background | hex-to-rgb
    let fg = $theme.special.foreground | hex-to-rgb
    let blend = {|t| passes (mix $bg $fg $t) $bg $BLEND_RATIO }
    let t = blend-floor $bg $fg $bg $BLEND_FROM $BLEND_STEP $BLEND_RATIO
    let lowest = $t != null and (do $blend $t) and ($t - $BLEND_STEP < $BLEND_FROM or not (do $blend ($t - $BLEND_STEP)))
    if not $lowest { error make {msg: $"palette.test: blend-floor gave ($t), not the lowest passing blend"} }
    if (blend-floor $bg $bg $bg 0.0 $BLEND_STEP $BLEND_RATIO) != null { error make {msg: "palette.test: blend-floor passed bg on bg"} }
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

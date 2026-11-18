#!/usr/bin/env -S nu --no-config-file
# The accent of a cover image: of its few dominant colours, the most colourful one that covers enough of it, skipping
# near-black and grey (near-white included). Prints `#RRGGBB`, or nothing when the image has no such colour. MediaState
# conditions it for contrast against the live background. One result per image content is kept in the cache dir.

const SAMPLE_PX = 64
const COLOR_COUNT = 8
const SHARE_MIN = 0.03
const VALUE_MIN = 0.2
const SATURATION_MIN = 0.25
const CACHE_KEEP = 200
const HISTOGRAM_LINE = '^\s*(?<count>\d+):\s*\(\s*(?<r>[\d.]+),\s*(?<g>[\d.]+),\s*(?<b>[\d.]+)'

def channel-to-hex [value: int]: nothing -> string {
    $value | format number | get lowerhex | str replace "0x" "" | fill --alignment right --character "0" --width 2
}

# Point samples, not a resize: averaging would invent blends of neighbouring colours along every edge.
export def art-accent-pick [file: path]: nothing -> string {
    let histogram = ^magick $"($file)[0]" -alpha off -sample $"($SAMPLE_PX)x($SAMPLE_PX)!" +dither -colors $COLOR_COUNT -depth 8 -format "%c" histogram:info:- | complete
    if $histogram.exit_code != 0 { return "" }
    let colors = $histogram.stdout | lines | parse --regex $HISTOGRAM_LINE
        | each {|row| {count: ($row.count | into int), rgb: ([$row.r $row.g $row.b] | each { into float | math round | into int })} }
    let total = $colors | get count | math sum
    if $total == 0 { return "" }
    let candidates = $colors | each {|color|
        let high = $color.rgb | math max
        let chroma = (($high - ($color.rgb | math min)) / 255)
        let value = $high / 255
        {rgb: $color.rgb, share: ($color.count / $total), value: $value, chroma: $chroma,
         saturation: (if $high == 0 { 0 } else { $chroma / $value })}
    } | where share >= $SHARE_MIN and value >= $VALUE_MIN and saturation >= $SATURATION_MIN
    if ($candidates | is-empty) { return "" }
    let best = $candidates | sort-by --reverse chroma share | first
    "#" + ($best.rgb | each {|c| channel-to-hex $c } | str join | str uppercase)
}

def cache-dir-default []: nothing -> path {
    ($env.XDG_RUNTIME_DIR? | default "/tmp") | path join quickshell art-accent
}

def main [file: path, --cache-dir: path]: nothing -> nothing {
    if not ($file | path exists) { return }
    let dir = $cache_dir | default (cache-dir-default)
    let entry = $dir | path join (open --raw $file | hash md5)
    if ($entry | path exists) { print --no-newline (open --raw $entry); return }
    let accent = art-accent-pick $file
    mkdir $dir
    $accent | save --force $entry
    ls $dir | sort-by --reverse modified | skip $CACHE_KEEP | each {|old| rm --force $old.name } | ignore
    print --no-newline $accent
}

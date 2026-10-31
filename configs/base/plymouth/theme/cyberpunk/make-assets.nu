#!/usr/bin/env -S nu --no-config-file

const HERE = path self | path expand | path dirname
const ACCENT = "#39bae6ff"
const TRACK = "#39bae659"
const ASSETS = [
    [file size color];
    [bar_fg.png 360x2 $ACCENT]
    [bar_bg.png 360x2 $TRACK]
    [caret.png 12x20 $ACCENT]
]

def main []: nothing -> nothing {
    if (which magick | is-empty) { error make --unspanned {msg: "make-assets: needs magick, from imagemagick"} }
    for asset in $ASSETS {
        ^magick -size $asset.size $"xc:($asset.color)" $"PNG32:($HERE | path join $asset.file)"
    }
    print $"wrote ($ASSETS.file | str join ' ')"
}

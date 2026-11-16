#!/usr/bin/env -S nu --no-config-file
# What a switch applies: a picked theme is that theme, a picked wallpaper derives its palette also when a theme names
# the file, and a rerun without a pick keeps what is recorded. A pick leads the last ones of its kind. magick's
# histogram reads as the picture's colours.

use wallpaper.nu [pick-resolve palette-kept recent-add picture-parse]

const THEMES = [
    [name wallpaper];
    [moonfly dresden.jpg]
    [void void.png]
    [both other.jpg]
]
const DERIVED = "pywal"

def main [] {
    let picks = [
        [name pick wallpaper palette];
        [theme-name moonfly dresden.jpg moonfly]
        [wallpaper-a-theme-names dresden.jpg dresden.jpg $DERIVED]
        [wallpaper-path /w/dresden.jpg /w/dresden.jpg $DERIVED]
        [wallpaper-no-theme-names lake.jpg lake.jpg $DERIVED]
        [bare-name-theme-and-file both other.jpg both]
        [file-of-that-stem both.jpg both.jpg $DERIVED]
        [path-of-that-stem ./both ./both $DERIVED]
    ]
    let kept = [
        [name recorded wallpaper palette];
        [theme-in-effect moonfly /w/dresden.jpg moonfly]
        [theme-on-another-wallpaper void /w/dresden.jpg void]
        [derived-in-effect $DERIVED /w/dresden.jpg $DERIVED]
        [no-record-theme-names-file "" /w/dresden.jpg moonfly]
        [no-record-no-theme "" /w/lake.jpg $DERIVED]
        [theme-removed gone /w/lake.jpg $DERIVED]
    ]
    let recent = [
        [name before file palette after];
        [first-theme {} /w/dresden.jpg moonfly {themes: [moonfly]}]
        [wallpaper-by-path {themes: [moonfly]} /w/lake.jpg $DERIVED {themes: [moonfly], wallpapers: [/w/lake.jpg]}]
        [again-moves-to-front {themes: [void moonfly]} /w/dresden.jpg moonfly {themes: [moonfly void]}]
        [oldest-dropped {wallpapers: [/w/a /w/b /w/c /w/d]} /w/e $DERIVED {wallpapers: [/w/e /w/a /w/b /w/c]}]
    ]
    let pictures = [
        [name text colours];
        [two-colours "       627: (11.0786,17.3222,23.2836) #0000FF srgb(4.3%,6.8%,9.1%)\n        13: (126,172,197.5) #FF0000 srgb(49%,67%,77%)\n" [{rgb: [0.0 0.0 1.0], count: 627} {rgb: [1.0 0.0 0.0], count: 13}]]
        [with-alpha "  4096: (0,255,0,255) #00FF00FF srgba(0,255,0,1)\n" [{rgb: [0.0 1.0 0.0], count: 4096}]]
        [no-histogram "magick: no decode delegate for this image format\n" []]
        [empty "" []]
    ]
    let failed = $picks | where {|c| (pick-resolve $c.pick $THEMES) != {wallpaper: $c.wallpaper, palette: $c.palette} }
        | append ($kept | where {|c| (palette-kept $c.recorded $c.wallpaper $THEMES) != $c.palette })
        | append ($recent | where {|c| (recent-add $c.before $c.file $c.palette) != $c.after })
        | append ($pictures | where {|c| ($c.text | picture-parse) != $c.colours }) | get name
    if ($failed | is-not-empty) { error make {msg: $"wallpaper.test: wrong result for ($failed | str join ', ')"} }
}

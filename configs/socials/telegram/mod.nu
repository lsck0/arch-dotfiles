use module.nu *

export const meta = {deps: [core/wallust], packages: {pacman: [imagemagick libarchive telegram-desktop]}}

const PALETTE_RENDERED = "colors-telegram.tdesktop-palette"
# a stable path in Telegram's own data dir: applied once from there (README.md), Telegram watches it and reloads
const THEME_FILE = "wallust.tdesktop-theme"
# the palette's key whose colour the chat background takes: a bare palette leaves Telegram's own green pattern
const BACKGROUND_KEY = "windowBg"

# the theme pass of an apply runs only the modules its link pass planned
export def link [cfg: record] { [] }

# A .tdesktop-theme is a zip of the palette and the chat background: a tiled.png repeats, so one plain tile paints the
# background in the palette's colour.
export def theme-build [rendered: path, dest: path]: nothing -> nothing {
    let text = open --raw $rendered
    let color = $text | lines | parse --regex '^(?<k>\w+): (?<c>#[0-9A-Fa-f]{6});' | where k == $BACKGROUND_KEY
        | get --optional 0.c
    if $color == null { error make {msg: $"telegram: ($rendered) has no plain ($BACKGROUND_KEY) colour"} }
    let stage = mktemp --directory
    $text | save ($stage | path join colors.tdesktop-theme)
    ^magick -size 8x8 $"xc:($color)" ($stage | path join tiled.png)
    let part = $"($dest).part"
    do { cd $stage; ^bsdtar --format zip -cf $part colors.tdesktop-theme tiled.png }
    rm --recursive --force $stage
    # in place, not renamed over: Telegram's watcher follows the file it applied
    open --raw $part | save --force $dest
    rm $part
}

export def theme [cfg: record, wallpaper: string] {
    let rendered = xdg cache wal $PALETTE_RENDERED
    if not ($rendered | path exists) { return [] }
    let dest = xdg data TelegramDesktop $THEME_FILE
    [(step theme-build $rendered $dest --key (open --raw $rendered | hash sha256) --creates $dest)]
}

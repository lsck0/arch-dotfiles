use module.nu *
use ../../core/wallust/palette.nu [opacity-shell]
use ../../core/wallust/font.nu [font-load]

export const meta = {packages: {pacman: [kitty]}}

export def link [cfg: record] {
    let dir = xdg config kitty
    [
        (file-render kitty.conf ($dir | path join kitty.conf) {CACHE: (xdg cache)})
    ]
}

export def theme [cfg: record, wallpaper: string] {
    let font = font-load
    [
        (file-text (xdg config kitty dotfiles-font.conf) $"font_family ($font.mono)\nfont_size ($font.size)\n" --generated)
        (file-text (xdg config kitty dotfiles-style.conf) $"background_opacity (opacity-shell)\n" --generated)
        (if (process-running kitty) { exec kitty-reload [pkill -USR1 -x kitty] })
    ]
}

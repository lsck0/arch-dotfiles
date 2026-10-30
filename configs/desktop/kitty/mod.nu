use module.nu *
use ../../core/wallust/palette.nu [OPACITY_SURFACE]
use ../../core/wallust/font.nu [font-load]

export const meta = {packages: {pacman: [kitty]}}

export def link [cfg: record] {
    let dir = xdg config kitty
    [
        (file-render kitty.conf ($dir | path join kitty.conf) {CACHE: (xdg cache)})
        (file-text ($dir | path join dotfiles-style.conf) $"background_opacity ($OPACITY_SURFACE)\n" --generated)
    ]
}

export def theme [cfg: record, wallpaper: string] {
    let font = font-load
    [
        (file-text (xdg config kitty dotfiles-font.conf) $"font_family ($font.mono)\nfont_size ($font.size)\n" --generated)
        (if (process-running kitty) { exec kitty-reload [pkill -USR1 -x kitty] } else { [] })
    ]
}

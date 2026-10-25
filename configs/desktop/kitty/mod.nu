use module.nu *
use ../../core/wallust/palette.nu [OPACITY_SURFACE]
use ../../core/wallust/font.nu [font-load]

export const meta = {packages: {pacman: [kitty]}}

export def link [cfg: record] {
    let dir = $nu.home-dir | path join .config kitty
    [
        (file-copy kitty.conf ($dir | path join kitty.conf))
        (file-text ($dir | path join dotfiles-style.conf) $"background_opacity ($OPACITY_SURFACE)\n" --generated)
    ]
}

export def theme [cfg: record, wallpaper: string] {
    let font = font-load
    [
        (file-text ($nu.home-dir | path join .config kitty dotfiles-font.conf) $"font_family ($font.mono)\nfont_size ($font.size)\n" --generated)
        (if (^pgrep -x kitty | complete).exit_code != 0 { [] } else { exec kitty-reload [pkill -USR1 -x kitty] })
    ]
}

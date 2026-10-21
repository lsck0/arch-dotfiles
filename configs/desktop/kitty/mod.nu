use module.nu *
use ../../core/wallust/palette.nu [OPACITY_SURFACE]

export const meta = {packages: {pacman: [kitty]}}

export def link [cfg: record] {
    let dir = $nu.home-dir | path join .config kitty
    [
        # a link: toggle-font rewrites the repo file
        (file-link kitty.conf ($dir | path join kitty.conf))
        (file-text ($dir | path join dotfiles-style.conf) $"background_opacity ($OPACITY_SURFACE)\n" --generated)
    ]
}

export def theme [cfg: record, wallpaper: string] {
    if (^pgrep -x kitty | complete).exit_code != 0 { return [] }
    exec kitty-reload [pkill -USR1 -x kitty]
}

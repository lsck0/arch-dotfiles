use module.nu *
use ../../core/wallust/scripts/palette.nu [ACCENT_RATIO blend-floor hex-to-rgb opacity-shell palette-load]
use ../../core/wallust/scripts/font.nu [font-load]

export const meta = {packages: {pacman: [kitty]}}

# kitty draws dim (SGR 2) text as the foreground at dim_opacity over the cell: its default, 0.4, is the lowest, raised
# in these steps until dim text keeps the dim-text floor (color8's) on the background
const DIM_OPACITY_MIN = 0.4
const DIM_OPACITY_STEP = 0.05

export def link [cfg: record] {
    let dir = xdg config kitty
    [
        (file-render config/kitty.conf ($dir | path join kitty.conf) {CACHE: (xdg cache)})
    ]
}

export def theme [cfg: record, wallpaper: string] {
    let font = font-load
    let p = palette-load
    let dim = if $p == null { "" } else {
        let bg = $p.bg | hex-to-rgb
        let a = blend-floor $bg ($p.fg | hex-to-rgb) $bg $DIM_OPACITY_MIN $DIM_OPACITY_STEP $ACCENT_RATIO | default 1.0
        $"dim_opacity ($a | math round --precision 2)\n"
    }
    [
        (file-text (xdg config kitty dotfiles-font.conf) $"font_family ($font.mono)\nfont_size ($font.size)\n" --generated)
        (file-text (xdg config kitty dotfiles-style.conf) $"background_opacity (opacity-shell)\n($dim)" --generated)
        (if (process-running kitty) { exec kitty-reload [pkill -USR1 -x kitty] })
    ]
}

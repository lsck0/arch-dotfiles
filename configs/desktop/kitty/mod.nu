use module.nu *
use ../../core/wallust/scripts/palette.nu [ACCENT_RATIO hex-to-rgb mix opacity-shell palette-load passes]
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

# The dim_opacity for palette p (a `palette-load` record): the lowest step at which fg over bg reaches ACCENT_RATIO.
export def dim-opacity [p: record]: nothing -> float {
    let bg = $p.bg | hex-to-rgb
    let fg = $p.fg | hex-to-rgb
    let steps = (1.0 - $DIM_OPACITY_MIN) / $DIM_OPACITY_STEP | math round
    0..$steps | each {|i| $DIM_OPACITY_MIN + $i * $DIM_OPACITY_STEP | math round --precision 2 }
        | where {|a| passes (mix $bg $fg $a) $bg $ACCENT_RATIO } | get --optional 0 | default 1.0
}

export def theme [cfg: record, wallpaper: string] {
    let font = font-load
    let p = palette-load
    let dim = if $p == null { "" } else { $"dim_opacity (dim-opacity $p)\n" }
    [
        (file-text (xdg config kitty dotfiles-font.conf) $"font_family ($font.mono)\nfont_size ($font.size)\n" --generated)
        (file-text (xdg config kitty dotfiles-style.conf) $"background_opacity (opacity-shell)\n($dim)" --generated)
        (if (process-running kitty) { exec kitty-reload [pkill -USR1 -x kitty] })
    ]
}

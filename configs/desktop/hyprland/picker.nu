#!/usr/bin/env -S nu --no-config-file

use ../../core/wallust/font.nu [font-load]
use ../../core/wallust/palette.nu [condition-bg hex-to-rgb readable-on rgb-to-hex wal-load]

const DEFAULTS = {bg: "#101010", fg: "#d0d0d0", accent: "#5f87af"}

# bemenu styled from the wallust palette and the theme's font; arguments go to bemenu.
def --wrapped main [...args: string]: nothing -> nothing {
    let wal = wal-load picker
    let slot = if $wal == null { {|name, fallback| $fallback | hex-to-rgb } } else { $wal }
    let font = font-load
    let surface = do $slot background $DEFAULTS.bg | condition-bg
    let accent_rgb = do $slot color2 $DEFAULTS.accent | readable-on $surface
    let bg = $surface | rgb-to-hex --prefix "#"
    let fg = do $slot foreground $DEFAULTS.fg | readable-on $surface | rgb-to-hex --prefix "#"
    let accent = $accent_rgb | rgb-to-hex --prefix "#"
    let highlight_fg = $surface | readable-on $accent_rgb | rgb-to-hex --prefix "#"
    (exec bemenu --ignorecase --list 15
        --fn $"($font.mono) ($font.size)"
        --tb $bg --tf $accent --fb $bg --ff $fg --nb $bg --nf $fg --hb $accent --hf $highlight_fg --scb $bg --scf $accent
        ...$args)
}

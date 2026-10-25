#!/usr/bin/env -S nu --no-config-file

const WAL_COLORS = "wal/colors"
# core/wallust's font.nu writes it resolved: family, mono (the fixed-pitch partner), size
const WAL_FONT = "wal/font.json"
const DEFAULTS = {bg: "#101010", fg: "#d0d0d0", accent: "#5f87af", font: monospace, size: "14"}

# bemenu styled from the wallust palette and the theme's font; arguments go to bemenu.
def --wrapped main [...args: string]: nothing -> nothing {
    let wal = $env.XDG_CACHE_HOME? | default ($nu.home-dir | path join .cache) | path join $WAL_COLORS
    let colors = if ($wal | path exists) { open --raw $wal | lines } else { [] }
    let color = {|index, fallback|
        $colors | get --optional $index | default "" | if $in == "" { $fallback } else { $in }
    }
    let font_file = $env.XDG_CACHE_HOME? | default ($nu.home-dir | path join .cache) | path join $WAL_FONT
    let font = try { open $font_file } catch { {} }
    let bg = do $color 0 $DEFAULTS.bg
    let fg = do $color 7 $DEFAULTS.fg
    let accent = do $color 2 $DEFAULTS.accent
    (exec bemenu --ignorecase --list 15
        --fn $"($font.mono? | default $DEFAULTS.font) ($font.size? | default $DEFAULTS.size)"
        --tb $bg --tf $accent --fb $bg --ff $fg --nb $bg --nf $fg --hb $accent --hf $bg --scb $bg --scf $accent
        ...$args)
}

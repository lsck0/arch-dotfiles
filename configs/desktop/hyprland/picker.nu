#!/usr/bin/env -S nu --no-config-file

const GHOSTTY_CONFIG = path self ../ghostty/config
const WAL_COLORS = "wal/colors"
const DEFAULTS = {bg: "#101010", fg: "#d0d0d0", accent: "#5f87af", font: monospace, size: "14"}

# bemenu styled from the wallust palette and ghostty's font; arguments go to bemenu.
def --wrapped main [...args: string]: nothing -> nothing {
    let wal = $env.XDG_CACHE_HOME? | default ($nu.home-dir | path join .cache) | path join $WAL_COLORS
    let colors = if ($wal | path exists) { open --raw $wal | lines } else { [] }
    let color = {|index, fallback|
        $colors | get --optional $index | default "" | if $in == "" { $fallback } else { $in }
    }
    let font = if ($GHOSTTY_CONFIG | path exists) { open --raw $GHOSTTY_CONFIG | lines | parse "{key} = {value}" }
        | default []
    let setting = {|key, fallback| $font | where key == $key | get --optional 0.value | default $fallback }
    let bg = do $color 0 $DEFAULTS.bg
    let fg = do $color 7 $DEFAULTS.fg
    let accent = do $color 2 $DEFAULTS.accent
    (exec bemenu --ignorecase --list 15
        --fn $"(do $setting font-family $DEFAULTS.font) (do $setting font-size $DEFAULTS.size)"
        --tb $bg --tf $accent --fb $bg --ff $fg --nb $bg --nf $fg --hb $accent --hf $bg --scb $bg --scf $accent
        ...$args)
}

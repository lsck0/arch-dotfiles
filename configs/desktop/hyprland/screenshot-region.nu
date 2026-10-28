#!/usr/bin/env -S nu --no-config-file
# slurp in the pywal palette instead of its white tint

const COLORS_JSON = "wal/colors.json"
const FALLBACK = {bg: "#0b0e14", accent: "#39bae6"}

def main [] {
    let cache = $env.XDG_CACHE_HOME? | default ($nu.home-dir | path join .cache)
    let wal = try { open ($cache | path join $COLORS_JSON) } catch { null }
    let bg = $wal.special?.background? | default $FALLBACK.bg | str trim --left --char "#"
    let accent = $wal.colors?.color4? | default $FALLBACK.accent | str trim --left --char "#"
    let region = ^slurp -b $"($bg)99" -c $"($accent)ff" -s $"($accent)22" -w 2 | complete
    if $region.exit_code != 0 { return }
    ^grim -g ($region.stdout | str trim) - | ^wl-copy
}

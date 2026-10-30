#!/usr/bin/env -S nu --no-config-file
# slurp in the wallust palette instead of its white tint

use ../../../scripts/lib/state.nu [xdg]

const COLORS_JSON = "wal/colors.json"
const FALLBACK = {bg: "#0b0e14", accent: "#39bae6"}

def main [] {
    let wal = try { open (xdg cache $COLORS_JSON) } catch { null }
    let bg = $wal.special?.background? | default $FALLBACK.bg | str trim --left --char "#"
    let accent = $wal.colors?.color4? | default $FALLBACK.accent | str trim --left --char "#"
    let region = ^slurp -b $"($bg)99" -c $"($accent)ff" -s $"($accent)22" -w 2 | complete
    if $region.exit_code != 0 { return }
    ^grim -g ($region.stdout | str trim) - | ^wl-copy
}

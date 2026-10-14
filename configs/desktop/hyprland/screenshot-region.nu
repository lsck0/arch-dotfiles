#!/usr/bin/env -S nu --no-config-file
# region screenshot to the clipboard; slurp in the pywal palette instead of its white tint: the screen dimmed with the
# background, the selection outlined in the accent (color4, as quickshell's Colors.accent) and lightly filled

const COLORS_JSON = ".cache/wal/colors.json"
const FALLBACK = {bg: "#0b0e14", accent: "#39bae6"}

def main [] {
    let wal = try { open ($nu.home-dir | path join $COLORS_JSON) } catch { null }
    let bg = $wal.special?.background? | default $FALLBACK.bg | str trim --left --char "#"
    let accent = $wal.colors?.color4? | default $FALLBACK.accent | str trim --left --char "#"
    # slurp takes rrggbbaa; cancelling the selection is no error
    let region = ^slurp -b $"($bg)99" -c $"($accent)ff" -s $"($accent)22" -w 2 | complete
    if $region.exit_code != 0 { return }
    ^grim -g ($region.stdout | str trim) - | ^wl-copy
}

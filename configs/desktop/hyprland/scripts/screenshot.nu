#!/usr/bin/env -S nu --no-config-file
# Screenshots a region, the focused output or the active window into ~/pictures/screenshots and copies the png. A
# success shows no toast, which the next screenshot would catch; a failure does. A cancel or a failed capture leaves
# the clipboard as it was; slurp draws in the wallust palette.

use ../../../core/wallust/scripts/palette.nu [palette-load]
use ../../quickshell/config/scripts/lib/shell.nu [action-notify]

const FALLBACK = {bg: "#0b0e14", c4: "#39bae6"}
const TITLE = "Screenshot"
const GLYPH = "\u{f0100}"

def notify [body: string]: nothing -> nothing { action-notify $GLYPH $TITLE $body }

# grim into a file first: piping into wl-copy would set an empty clipboard when grim fails.
def screenshot-save [grim_args: list<string>]: nothing -> nothing {
    let dir = $nu.home-dir | path join pictures screenshots
    mkdir $dir
    let file = $dir | path join $"(date now | format date '%Y-%m-%d_%H-%M-%S_%3f').png"
    let shot = ^grim ...$grim_args $file | complete
    if $shot.exit_code != 0 or not ($file | path exists) or (ls $file | get 0.size) == 0b {
        rm -f $file
        notify $"Capture failed: ($shot.stderr | str trim | default --empty 'empty image')"
        return
    }
    open --raw $file | ^wl-copy --type image/png
}

def main []: nothing -> nothing {
    print -e "usage: screenshot.nu region|output|window"
    exit 1
}

def "main region" []: nothing -> nothing {
    let palette = palette-load | default $FALLBACK
    let bg = $palette.bg | str trim --left --char "#"
    let accent = $palette.c4 | str trim --left --char "#"
    let region = ^slurp -b $"($bg)99" -c $"($accent)ff" -s $"($accent)22" -w 2 | complete
    if $region.exit_code != 0 { return }
    screenshot-save [-g ($region.stdout | str trim)]
}

def "main output" []: nothing -> nothing {
    let output = ^hyprctl -j monitors | from json | where focused | get 0?.name
    if $output == null { notify "No focused output"; return }
    screenshot-save [-o $output]
}

def "main window" []: nothing -> nothing {
    let window = ^hyprctl -j activewindow | from json
    if $window.at? == null or $window.size? == null { notify "No active window"; return }
    screenshot-save [-g $"($window.at.0),($window.at.1) ($window.size.0)x($window.size.1)"]
}

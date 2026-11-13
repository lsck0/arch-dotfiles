#!/usr/bin/env -S nu --no-config-file
# Screenshots a region, the focused output or the active window into ~/pictures/screenshots, copies the png and
# notifies with it. A cancel or a failed capture leaves the clipboard as it was; slurp draws in the wallust palette.

use ../../core/wallust/palette.nu [wal-colors-file]

const FALLBACK = {bg: "#0b0e14", accent: "#39bae6"}
const NOTIFY_APP = "quickshell-action"
const TITLE = "Screenshot"

def notify [body: string, --icon: path]: nothing -> nothing {
    let icon_args = if $icon == null { [] } else { [-i $icon] }
    ^notify-send -a $NOTIFY_APP -u low ...$icon_args -- $TITLE $body
}

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
    notify $file --icon $file
}

def main []: nothing -> nothing {
    print -e "usage: screenshot.nu region|output|window"
    exit 1
}

def "main region" []: nothing -> nothing {
    let wal = try { open (wal-colors-file) } catch { null }
    let bg = $wal.special?.background? | default $FALLBACK.bg | str trim --left --char "#"
    let accent = $wal.colors?.color4? | default $FALLBACK.accent | str trim --left --char "#"
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

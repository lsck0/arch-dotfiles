#!/usr/bin/env -S nu --no-config-file

const HERE = path self | path expand | path dirname
use ($HERE | path join lib shell.nu) [SHELL_CONFIG shell-call]

const VOLUME_STEP_PERCENT = 5
const VOLUME_MAX_PERCENT = 100
const BRIGHTNESS_STEP_PERCENT = 5
# color-grading.py's BRIGHTNESS_PERCENT_MAX: the matrix scale goes past full
const SOFTWARE_BRIGHTNESS_MAX_PERCENT = 150
const MONITOR_BRIGHTNESS = ($SHELL_CONFIG | path join scripts monitor-brightness.nu)

def osd [icon: string, field: string, value: any]: nothing -> nothing {
    shell-call osd present ({icon: $icon, $field: $value} | to json -r) | complete | ignore
}

def sink-volume []: nothing -> int {
    pactl get-sink-volume @DEFAULT_SINK@ | parse -r '(?<percent>\d+)%' | get 0.percent | into int
}

def volume-osd []: nothing -> nothing {
    if (pactl get-sink-mute @DEFAULT_SINK@) =~ yes { osd volume-muted message Muted } else { osd volume value (sink-volume) }
}

# Uses -c backlight: without a backlight brightnessctl falls back to the first led (numlock on a desktop).
def backlight-percent []: nothing -> int {
    let max = brightnessctl -c backlight -m max | into int
    if $max > 0 { (brightnessctl -c backlight -m get | into int) * 100 // $max } else { 0 }
}

def brightness-step [delta: int]: nothing -> nothing {
    if (glob /sys/class/backlight/* | is-empty) {
        # coalesce repeats only, a press while one is in flight is dropped: a lock of its own, never the ddc-i2c.lock
        # the called monitor-brightness takes for the bus, or _ddc-step would deadlock waiting on a lock its parent holds
        let lock = $env.XDG_RUNTIME_DIR | path join media-key-ddc.lock
        ^flock -n -E 0 $lock $env.CURRENT_FILE _ddc-step $delta
        return
    }
    let sign = if $delta > 0 { "+" } else { "-" }
    brightnessctl -q -c backlight set $"($delta | math abs)%($sign)"
    if (backlight-percent) < 1 { brightnessctl -q -c backlight set 1% }
    osd brightness value (backlight-percent)
}

# The bar's player through the shell's media target; playerctl's first player while the shell is down or has none.
def media-step [ipc_function: string, playerctl_verb: string, icon: string]: nothing -> nothing {
    let call = shell-call media $ipc_function | complete
    # anything but the handler's json (an older shell without the media target) falls back too
    let shown = if $call.exit_code == 0 { try { $call.stdout | from json | select icon title } catch { null } }
    if $shown != null {
        osd $shown.icon message $shown.title
        return
    }
    let fallback = ^playerctl $playerctl_verb | complete
    if $fallback.exit_code != 0 { osd $icon message "No player"; return }
    osd $icon message (^playerctl metadata title | complete | get stdout | str trim)
}

# The color-grading matrix scale, for outputs ddc and the backlight cannot reach.
def software-brightness-step [delta: int]: nothing -> nothing {
    let grading = $env.DOTFILES | path join configs desktop color-grading color-grading.py
    let sign = if $delta > 0 { "+" } else { "-" }
    let set = ^$grading set brightness $"($sign)($delta | math abs)" | complete
    if $set.exit_code != 0 { osd brightness message "No color grading"; return }
    let percent = ^$grading get brightness | str trim | into int
    let shown = {icon: brightness, value: $percent, max: $SOFTWARE_BRIGHTNESS_MAX_PERCENT, progressText: $"($percent)%"}
    shell-call osd present ($shown | to json -r) | complete | ignore
}

def kbd-step [next_from: closure]: nothing -> nothing {
    let device = glob /sys/class/leds/*kbd_backlight*/brightness | get 0? | default "" | path dirname | path basename
    if $device == "" { osd keyboard-backlight-off message "No keyboard backlight"; return }
    let current = brightnessctl -d $device -m get | into int
    let max = brightnessctl -d $device -m max | into int
    let next = do $next_from $current $max
    brightnessctl -q -d $device set $next
    if $next == 0 { osd keyboard-backlight-off message "Keyboard light off" } else { osd keyboard-backlight value ($next * 100 // $max) }
}

def main []: nothing -> nothing {
    print -e $"usage: (scope commands | where name =~ '^main [a-z]' | get name | str replace 'main ' '' | str join '|')"
    exit 1
}

def "main volume-up" []: nothing -> nothing {
    let target = [$VOLUME_MAX_PERCENT ((sink-volume) + $VOLUME_STEP_PERCENT)] | math min
    pactl set-sink-volume @DEFAULT_SINK@ $"($target)%"
    pactl set-sink-mute @DEFAULT_SINK@ 0
    volume-osd
}

def "main volume-down" []: nothing -> nothing {
    pactl set-sink-volume @DEFAULT_SINK@ $"-($VOLUME_STEP_PERCENT)%"
    volume-osd
}

def "main volume-mute" []: nothing -> nothing {
    pactl set-sink-mute @DEFAULT_SINK@ toggle
    volume-osd
}

def "main mic-mute" []: nothing -> nothing {
    pactl set-source-mute @DEFAULT_SOURCE@ toggle
    if (pactl get-source-mute @DEFAULT_SOURCE@) =~ yes { osd microphone-muted message "Mic muted" } else { osd microphone message "Mic live" }
}

def "main play-pause" []: nothing -> nothing { media-step playPause play-pause media-play }

def "main next" []: nothing -> nothing { media-step next next media-next }

def "main previous" []: nothing -> nothing { media-step previous previous media-previous }

def "main stop" []: nothing -> nothing { media-step stop stop media-stop }

def "main brightness-up" []: nothing -> nothing { brightness-step $BRIGHTNESS_STEP_PERCENT }

def "main brightness-down" []: nothing -> nothing { brightness-step (0 - $BRIGHTNESS_STEP_PERCENT) }

def "main software-brightness-up" []: nothing -> nothing { software-brightness-step $BRIGHTNESS_STEP_PERCENT }

def "main software-brightness-down" []: nothing -> nothing { software-brightness-step (0 - $BRIGHTNESS_STEP_PERCENT) }

def "main kbd-backlight-up" []: nothing -> nothing { kbd-step {|current, max| [($current + 1) $max] | math min } }

def "main kbd-backlight-down" []: nothing -> nothing { kbd-step {|current, max| [($current - 1) 0] | math max } }

# cycle so the dim step is reachable
def "main kbd-backlight-toggle" []: nothing -> nothing { kbd-step {|current, max| ($current + 1) mod ($max + 1) } }

def "main _ddc-step" [delta: int]: nothing -> nothing {
    let monitor = hyprctl monitors -j | from json | where focused | get 0.name
    let current = ^$MONITOR_BRIGHTNESS get $monitor | complete | get stdout | str trim
    if $current !~ '^\d+$' { osd brightness message "No brightness control"; return }
    let next = $current | into int | $in + $delta | [$in 100] | math min | [$in 1] | math max
    ^$MONITOR_BRIGHTNESS set $monitor $next
    osd brightness value $next
}

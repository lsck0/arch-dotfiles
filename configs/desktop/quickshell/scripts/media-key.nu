#!/usr/bin/env -S nu --no-config-file

const VOLUME_STEP_PERCENT = 5
const VOLUME_MAX_PERCENT = 100
const BRIGHTNESS_STEP_PERCENT = 5
const SHELL_CONFIG = ($nu.home-dir | path join .config quickshell)
const MONITOR_BRIGHTNESS = ($SHELL_CONFIG | path join scripts monitor-brightness.nu)

def osd [icon: string, field: string, value: any]: nothing -> nothing {
    ^timeout 2 quickshell ipc -p $SHELL_CONFIG call osd present ({icon: $icon, $field: $value} | to json -r)
    | complete | ignore
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

def "main brightness-up" []: nothing -> nothing { brightness-step $BRIGHTNESS_STEP_PERCENT }

def "main brightness-down" []: nothing -> nothing { brightness-step (0 - $BRIGHTNESS_STEP_PERCENT) }

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

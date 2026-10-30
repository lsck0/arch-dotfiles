#!/usr/bin/env -S nu --no-config-file

const STEP_DELAY = 40ms
const STEPS = 12
const USER_MOVE_PX = 30
const PAUSE_MIN_MS = 200

def cursor []: nothing -> record {
    ^hyprctl cursorpos | split row "," | each { str trim | into int } | {x: $in.0, y: $in.1}
}

def nudge [dx: int, dy: int]: nothing -> nothing {
    if $dx != 0 or $dy != 0 { ^ydotool mousemove -x $dx -y $dy | ignore }
}

def glide [target: record]: nothing -> record {
    for i in 1..$STEPS {
        let now = cursor
        let left = $STEPS - $i + 1
        nudge (($target.x - $now.x) / $left | math round) (($target.y - $now.y) / $left | math round)
        sleep $STEP_DELAY
    }
    let now = cursor
    nudge ($target.x - $now.x) ($target.y - $now.y)
    cursor
}

# Jitter the mouse randomly around where it is now, within --radius logical pixels, until ctrl+c.
def main [
    --radius: int = 55  # logical pixels; about 1.5 cm at 4K and scale 1.67
    --pause: duration = 1500ms  # longest rest between moves
]: nothing -> nothing {
    # stopped on exit only when this run started it
    let started = (^systemctl --user is-active ydotool | complete).exit_code != 0
    if $started { ^systemctl --user start ydotool }
    try {
        mut centre = cursor
        mut last = $centre
        loop {
            let now = cursor
            if (($now.x - $last.x) | math abs) > $USER_MOVE_PX or (($now.y - $last.y) | math abs) > $USER_MOVE_PX {
                $centre = $now
            }
            let angle = random float 0..6.283
            let dist = random float 0..($radius | into float)
            let target = {
                x: ($centre.x + ($angle | math cos) * $dist | math round)
                y: ($centre.y + ($angle | math sin) * $dist | math round)
            }
            $last = glide $target
            # a --pause under PAUSE_MIN_MS would make a descending range
            let hi = [$PAUSE_MIN_MS ($pause / 1ms | into int)] | math max
            sleep (random int $PAUSE_MIN_MS..$hi | into duration --unit ms)
        }
    } finally {
        if $started { ^systemctl --user stop ydotool }
    }
}

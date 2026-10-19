#!/usr/bin/env -S nu --no-config-file

const STEP_DELAY = 40ms
const STEPS = 12
# a cursor this far from where the last step left it means the user moved it: that spot becomes the new centre
const USER_MOVE_PX = 30

def cursor []: nothing -> record {
    ^hyprctl cursorpos | split row "," | each { str trim | into int } | {x: $in.0, y: $in.1}
}

def nudge [dx: int, dy: int]: nothing -> nothing {
    if $dx != 0 or $dy != 0 { ^ydotool mousemove -x $dx -y $dy | ignore }
}

# glides to a target in small steps, correcting from the real position so pointer acceleration cannot drift it away
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

# jitters the mouse randomly around where it is now, within --radius logical pixels, until ctrl+c
def main [
    --radius: int = 55  # logical pixels; about 1.5 cm at 4K and scale 1.67
    --pause: duration = 1500ms  # longest rest between moves
] {
    if (^systemctl --user is-active ydotool | complete).exit_code != 0 { ^systemctl --user start ydotool }
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
        sleep (random int 200..($pause / 1ms | into int) | into duration --unit ms)
    }
}

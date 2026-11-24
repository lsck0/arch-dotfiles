#!/usr/bin/env -S nu --no-config-file

# games inside gamescope ignore a close request (Median XL saves only through its own menu), so that window is killed
const FORCE_CLASSES = [gamescope]
const TERM_GRACE = 2sec

def main [] {
    let window = ^hyprctl -j activewindow | from json
    if ($window | is-empty) { return }
    if $window.class not-in $FORCE_CLASSES {
        ^hyprctl dispatch "hl.dsp.window.close()" | ignore
        return
    }
    ^kill -TERM $window.pid
    sleep $TERM_GRACE
    if ($"/proc/($window.pid)" | path exists) { ^kill -KILL $window.pid }
}

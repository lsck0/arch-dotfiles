#!/usr/bin/env -S nu --no-config-file
# quickshell lock, hyprlock when quickshell is unreachable; a locker not holding the compositor's lock is no lock

const LOCK_POLL_TRIES = 30
const LOCK_POLL_INTERVAL = 100ms

def running [name: string]: nothing -> bool {
    (^pgrep -x $name -u $env.USER | complete).exit_code == 0
}

def locked []: nothing -> bool {
    try { ^hyprctl -j locked | from json | get locked } catch { false }
}

# As a before_sleep_cmd barrier: keeps the freeze from racing the lock handshake, which aborts quickshell.
def granted []: nothing -> bool {
    1..$LOCK_POLL_TRIES | each { $in } | any {|_| if (locked) { true } else { sleep $LOCK_POLL_INTERVAL; false } }
}

def main [] {
    if (locked) { return }
    if (which quickshell | is-not-empty) and (running quickshell) {
        let config = $env.XDG_CONFIG_HOME? | default ($nu.home-dir | path join .config) | path join quickshell
        let asked = ^timeout 5s quickshell ipc -p $config call lock lock | complete | get stdout | str trim
        if $asked == "ok" and (granted) { return }
    }
    if (which hyprlock | is-not-empty) {
        # a leftover one that never got the lock would refuse the new one
        ^pkill -x -u $env.USER hyprlock | complete | ignore
        ^setsid -f hyprlock --grace 0 --immediate-render o+e> /dev/null
        if (granted) { return }
    }
    ^notify-send -u critical lock "quickshell and hyprlock unreachable, cannot lock" | complete | ignore
    ^hyprctl dispatch "hl.dsp.dpms({ mode = 'off' })" | complete | ignore
    exit 1
}

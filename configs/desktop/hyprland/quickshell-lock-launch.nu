#!/usr/bin/env -S nu --no-config-file
# hyprlock if lock_screen=hyprlock, then quickshell, then hyprlock (a second try in that case); a locker not holding the compositor's lock is no lock

const DPMS = path self dpms.nu
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
    for _ in 1..$LOCK_POLL_TRIES {
        if (locked) { return true }
        sleep $LOCK_POLL_INTERVAL
    }
    false
}

def config-dir []: nothing -> path { $env.XDG_CONFIG_HOME? | default ($nu.home-dir | path join .config) }

# desktop/hyprland's lock_screen option, written beside this script's config
def preferred []: nothing -> string {
    try { open --raw (config-dir | path join hypr locker) | str trim } catch { "quickshell" }
}

def hyprlock-take []: nothing -> bool {
    if (which hyprlock | is-empty) { return false }
    # a leftover one that never got the lock would refuse the new one
    ^pkill -x -u $env.USER hyprlock | complete | ignore
    ^setsid -f hyprlock --grace 0 --immediate-render o+e> /dev/null
    granted
}

def main [] {
    if (locked) { return }
    if (preferred) == "hyprlock" and (hyprlock-take) { return }
    if (which quickshell | is-not-empty) and (running quickshell) {
        let asked = ^timeout 5s quickshell ipc -p (config-dir | path join quickshell) call lock lock | complete | get stdout | str trim
        if $asked == "ok" and (granted) { return }
    }
    if (hyprlock-take) { return }
    ^notify-send -u critical "Screen not locked" "quickshell and hyprlock both failed to take the lock" | complete | ignore
    ^$DPMS off | complete | ignore
    exit 1
}

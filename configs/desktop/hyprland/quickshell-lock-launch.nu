#!/usr/bin/env -S nu --no-config-file
# route lock requests to the quickshell lock, hyprlock when quickshell is unreachable; no-op if already locked

const LOCK_POLL_TRIES = 30
const LOCK_POLL_INTERVAL = 100ms

def running [name: string]: nothing -> bool {
    (^pgrep -x $name -u $env.USER | complete).exit_code == 0
}

def qs-call [timeout: string, ...args: string]: nothing -> string {
    let config = $env.XDG_CONFIG_HOME? | default ($nu.home-dir | path join .config) | path join quickshell
    ^timeout $timeout quickshell ipc -p $config call lock ...$args | complete | get stdout | str trim
}

def main [] {
    if (running hyprlock) { return }
    if (which quickshell | is-not-empty) and (running quickshell) {
        if (qs-call 3s isLocked) == "true" { return }
        if (qs-call 5s lock) == "ok" {
            # wait for the compositor to grant the lock before returning; as a before_sleep_cmd barrier this keeps the
            # freeze from racing the ext-session-lock handshake, which aborts quickshell mid-suspend
            for _ in 1..$LOCK_POLL_TRIES {
                if (qs-call 1s isLocked) == "true" { return }
                sleep $LOCK_POLL_INTERVAL
            }
            # never granted: refused or stuck handshake, fall through to hyprlock
        }
    }
    if (which hyprlock | is-not-empty) {
        ^setsid -f hyprlock --grace 0 --immediate-render o+e> /dev/null
        # hyprlock reports no lock state, so it counts as held once it survives the wait; a refused lock or bad config
        # exits early
        for _ in 1..$LOCK_POLL_TRIES {
            if not (running hyprlock) { break }
            sleep $LOCK_POLL_INTERVAL
        }
        if (running hyprlock) { return }
    }
    # no locker left: blank and fail rather than fake a lock
    ^notify-send -u critical lock "quickshell and hyprlock unreachable, cannot lock" | complete | ignore
    ^hyprctl dispatch "hl.dsp.dpms({ mode = 'off' })" | complete | ignore
    exit 1
}

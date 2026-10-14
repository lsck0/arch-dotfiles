#!/usr/bin/env -S nu --no-config-file
# re-sources tmux.conf for the lifetime of its server; not b0o/tmux-autoreload: its entr watcher outlived the server

const SELF = path self

# run-shell blocks until stdout closes, so detach fully; every reload reruns this, the lock keeps one per server
def main [--watch]: nothing -> nothing {
    let socket = $env.TMUX | split row "," | first
    if not $watch {
        "" | ^setsid -f flock -n $"($socket).autoreload.lock" $SELF --watch o+e> /dev/null
        return
    }
    let conf = $nu.home-dir | path join .config tmux tmux.conf | path expand
    let entr = job spawn {
        $conf | ^entr -np tmux -S $socket source-file $conf ";" display-message "tmux.conf reloaded"
    }
    # pidfd wait, no polling: returns once the server is gone, whether it exited or was killed
    try { ^waitpid ($env.TMUX | split row "," | get 1) }
    job kill $entr
}

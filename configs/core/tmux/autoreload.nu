#!/usr/bin/env -S nu --no-config-file
const SELF = path self

# Re-source tmux.conf on change for the lifetime of this tmux server; the lock keeps one watcher per server.
def main [--watch]: nothing -> nothing {
    let socket = $env.TMUX | split row "," | first
    if not $watch {
        # run-shell blocks until stdout closes, so detach fully
        "" | ^setsid -f flock -n $"($socket).autoreload.lock" $SELF --watch o+e> /dev/null
        return
    }
    let conf = $nu.home-dir | path join .config tmux tmux.conf | path expand
    let entr = job spawn {
        $conf | ^entr -np tmux -S $socket source-file $conf ";" display-message "tmux.conf reloaded"
    }
    try { ^waitpid ($env.TMUX | split row "," | get 1) }
    job kill $entr
}

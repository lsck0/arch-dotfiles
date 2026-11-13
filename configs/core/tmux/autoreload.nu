#!/usr/bin/env -S nu --no-config-file
const SELF = path self
# installed beside the tmux.conf it watches
const CONF = path self tmux.conf

# Re-source tmux.conf on change for the lifetime of this tmux server; the lock keeps one watcher per server.
def main [--watch]: nothing -> nothing {
    let tmux = $env.TMUX | split row ","
    let socket = $tmux.0
    if not $watch {
        # run-shell blocks until stdout closes, so detach fully
        "" | ^setsid -f flock -n $"($socket).autoreload.lock" $SELF --watch o+e> /dev/null
        return
    }
    let entr = job spawn {
        $CONF | ^entr -np tmux -S $socket source-file $CONF ";" display-message "tmux.conf reloaded"
    }
    try { ^waitpid $tmux.1 }
    job kill $entr
}

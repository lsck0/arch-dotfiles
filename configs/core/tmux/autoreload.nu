#!/usr/bin/env -S nu --no-config-file
# re-sources tmux.conf on change for exactly the lifetime of the server that ran it; replaces b0o/tmux-autoreload,
# whose entr watcher outlived its server so every tms/popup/scripted server leaked a pair

const SELF = path self

# run-shell sets TMUX=<socket>,<server pid>,<session> and blocks until stdout closes, so the watcher detaches fully;
# tmux.conf runs this on every reload too: the lock keeps one watcher per server
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

#!/usr/bin/env -S nu --no-config-file
# hollywood-run: hollywood on a tmux server of its own with no config. on the user's server it breaks: tmux.conf's
# base-index 1 misses its 0-based pane targets, and run inside a session it only adds a window there and exits

const SERVER = "hollywood"
# hollywood calls tmux (and byobu, when found) by name, so both resolve to the private server; sh, since hollywood
# runs it for every tmux call
const SHIM = "#!/bin/sh\nexec /usr/bin/tmux -L hollywood -f /dev/null \"$@\"\n"

def --wrapped main [...args: string]: nothing -> nothing {
    let bin = $env.XDG_RUNTIME_DIR? | default /tmp | path join hollywood-run
    mkdir $bin
    $SHIM | save --force ($bin | path join tmux)
    ^chmod +x ($bin | path join tmux)
    ^ln -sfn tmux ($bin | path join byobu)
    $env.PATH = $env.PATH | prepend $bin
    hide-env --ignore-errors TMUX
    # inside the session hollywood splits the current window and kills the session once it quits
    ^tmux kill-server | complete | ignore
    let size = term size
    let command = [hollywood ...($args | each { $"'($in | str replace --all "'" "'\\''")'" })] | str join " "
    ^tmux new-session -d -s $SERVER -x $size.columns -y $size.rows $command
    exec tmux attach-session -t $SERVER
}

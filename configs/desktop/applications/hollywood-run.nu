#!/usr/bin/env -S nu --no-config-file
# its own tmux server with no config: tmux.conf's base-index 1 misses its 0-based pane targets

const SERVER = "hollywood"
# hollywood calls tmux (and byobu) by name for every call, so both resolve to the private server
const SHIM = "#!/bin/sh\nexec /usr/bin/tmux -L hollywood -f /dev/null \"$@\"\n"

def --wrapped main [...args: string]: nothing -> nothing {
    if ($args | get --optional 0) in ["-h" "--help"] { print "usage: hollywood-run [args...]: hollywood on a private tmux server"; return }
    let bin = $env.XDG_RUNTIME_DIR? | default /tmp | path join hollywood-run
    mkdir $bin
    $SHIM | save --force ($bin | path join tmux)
    ^chmod +x ($bin | path join tmux)
    ^ln -sfn tmux ($bin | path join byobu)
    $env.PATH = $env.PATH | prepend $bin
    hide-env --ignore-errors TMUX
    ^tmux kill-server | complete | ignore
    let size = term size
    let command = [hollywood ...($args | each { $"'($in | str replace --all "'" "'\\''")'" })] | str join " "
    ^tmux new-session -d -s $SERVER -x $size.columns -y $size.rows $command
    exec tmux attach-session -t $SERVER
}

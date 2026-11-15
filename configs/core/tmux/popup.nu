#!/usr/bin/env -S nu --no-config-file
const NOT_FOUND = 127

# Run <tool> [args...] in a tmux popup, -e with the pane dir's direnv env; a missing tool waits for a key.
def --wrapped main [...argv: string]: nothing -> nothing {
    let direnv = $argv.0? == "-e"
    if $direnv {
        let exported = do { ^direnv export json } | complete | get stdout
        let vars = if $exported == "" { {} } else { $exported | from json }
        let unset = $vars | items {|k, v| if $v == null { $k } } | compact
        for k in $unset { hide-env --ignore-errors $k }
        $vars | reject ...$unset | load-env
    }
    let argv = $argv | skip (if $direnv { 1 } else { 0 })
    let tool = $argv.0
    if (which $tool | is-empty) {
        input --numchar 1 --suppress-output $"($tool) is not installed \(its package group is not on this machine\), press any key"
        exit $NOT_FOUND
    }
    exec $tool ...($argv | skip 1)
}

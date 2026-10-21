#!/usr/bin/env -S nu --no-config-file
const NOT_FOUND = 127

# Run [sudo] <tool> [args...] in a tmux popup, -e with the pane dir's direnv env; a missing tool waits for a key.
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
    let tool = if $argv.0 == "sudo" { $argv.1 } else { $argv.0 }
    if (which $tool | is-empty) {
        let why = "its package group is not on this machine"
        input --numchar 1 --suppress-output $"($tool) is not installed \(($why)\), press any key"
        exit $NOT_FOUND
    }
    exec $argv.0 ...($argv | skip 1)
}

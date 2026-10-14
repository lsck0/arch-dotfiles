#!/usr/bin/env -S nu --no-config-file
# popup.nu [-e] [sudo] <tool> [args...]: tmux popup runner; -e loads the pane dir's direnv env (a failing .envrc is
# ignored), a tool a machine lacks reports instead of closing silently

const NOT_FOUND = 127

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

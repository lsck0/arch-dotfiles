#!/usr/bin/env -S nu --no-config-file

const PROMPT = '(λ|❯|[$%#])[[:space:]]*$'
const PROMPT_TIMEOUT_MS = 600000
# "<sha256>  <path>" per allowed .herdr-create: a cloned repo's script never runs until allowed, like direnv allow
const TRUST = ($nu.home-dir | path join .local state herdr create-allowed)

# Runs argv once the pane shows a prompt: herdr pane run drops keystrokes typed before direnv/devenv is ready.
def pane-run [pane: string, ...argv: string]: nothing -> nothing {
    let ready = do { ^herdr pane wait-output --regex $PROMPT --timeout $PROMPT_TIMEOUT_MS $pane } | complete
    if $ready.exit_code == 0 { ^herdr pane run $pane ...$argv | ignore }
}

def create-line [create: path]: nothing -> string { $"(open --raw $create | hash sha256)  ($create)" }

def create-allowed [create: path]: nothing -> bool {
    ($TRUST | path exists) and ((create-line $create) in (open --raw $TRUST | lines))
}

# Allow <dir>'s current .herdr-create; editing it afterwards needs a new allow.
def "main allow" [dir: path]: nothing -> nothing {
    let create = $dir | path join .herdr-create | path expand
    if not ($create | path exists) { error make {msg: $"no ($create)"} }
    let kept = if ($TRUST | path exists) { open --raw $TRUST | lines | where { not ($in | str ends-with $"  ($create)") } } else { [] }
    mkdir ($TRUST | path dirname)
    $kept | append (create-line $create) | str join "\n" | $"($in)\n" | save --force $TRUST
}

# Focus the herdr workspace for <dir>, or create it with nvim, claude and zsh tabs (or run its allowed .herdr-create).
def main [dir: path, label?: string]: nothing -> nothing {
    let label = $label | default ($dir | path basename)
    let listed = do { ^herdr workspace list } | complete
    let existing = if $listed.exit_code == 0 {
        $listed.stdout | from json | get result.workspaces | where label == $label | get --optional 0.workspace_id
    }
    if $existing != null {
        ^herdr workspace focus $existing | ignore
        return
    }
    let create = $dir | path join .herdr-create | path expand
    if ($create | path exists) and (ls --long $create | get 0.mode | str contains x) {
        if (create-allowed $create) { exec $create $label }
        let refused = $"($create)\nread it, then: herdr-open allow ($dir)"
        if (which notify-send | is-empty) { print --stderr $"herdr-open: .herdr-create not allowed: ($refused)" } else {
            ^notify-send -a herdr ".herdr-create not allowed" $refused | complete | ignore
        }
    }

    let created = ^herdr workspace create --cwd $dir --label $label --focus | from json | get result
    let first_tab = $created.tab.tab_id
    pane-run $created.root_pane.pane_id env NVIM_TMS=1 nvim
    ^herdr tab rename $first_tab nvim | ignore
    for app in [claude zsh] {
        let tab = ^herdr tab create --workspace $created.workspace.workspace_id --cwd $dir --no-focus
            | from json | get result
        ^herdr tab rename $tab.tab.tab_id $app | ignore
        if $app == claude { pane-run $tab.root_pane.pane_id claude }
    }
    ^herdr tab focus $first_tab | ignore
}

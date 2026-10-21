#!/usr/bin/env -S nu --no-config-file

const PROMPT = '(λ|❯|[$%#])[[:space:]]*$'
const PROMPT_TIMEOUT_MS = 600000

# Runs argv once the pane shows a prompt: herdr pane run drops keystrokes typed before direnv/devenv is ready.
def pane-run [pane: string, ...argv: string]: nothing -> nothing {
    let ready = do { ^herdr pane wait-output --regex $PROMPT --timeout $PROMPT_TIMEOUT_MS $pane } | complete
    if $ready.exit_code == 0 { ^herdr pane run $pane ...$argv | ignore }
}

# Focus the herdr workspace for <dir>, or create it with nvim, claude and zsh tabs (or run its .herdr-create).
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
    let create = $dir | path join .herdr-create
    if ($create | path exists) and (ls --long $create | get 0.mode | str contains x) { exec $create $label }

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

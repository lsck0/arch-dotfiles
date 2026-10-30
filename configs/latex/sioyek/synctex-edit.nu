#!/usr/bin/env -S nu --no-config-file

const ASK_TIMEOUT_S = "2"
const OPEN_TIMEOUT_S = "5"
const NOTIFY_APP = "quickshell-action"

def --wrapped ask [...argv: string]: nothing -> record {
    do { ^$argv.0 ...($argv | skip 1) } | complete
}

def nvim-try [file: string, line: int, column: int]: nothing -> bool {
    if (which nvim | is-empty) { return false }
    let log = $env.XDG_CACHE_HOME? | default ($nu.home-dir | path join .cache) | path join vimtex nvim_servernames.log
    let runtime = $env.XDG_RUNTIME_DIR? | default $"/run/user/(^id -u | str trim)"
    let listed = if ($log | path exists) { open --raw $log | lines } else { [] }
    let sockets = $listed ++ (glob ($runtime | path join "nvim.*"))
    let expr = $"vimtex#view#inverse_search\(($line), '($file | str replace --all "'" "''")', ($column)\)"
    $sockets | uniq | where ($it | path type) == socket | any {|sock|
        let answer = ask timeout $ASK_TIMEOUT_S nvim --server $sock --remote-expr $expr
        # vimtex answers <0 when no project in that instance owns the file, so every nvim can be asked safely
        $answer.exit_code == 0 and not ($answer.stdout | str trim | str starts-with "-")
    }
}

def emacs-try [file: string, line: int, column: int]: nothing -> bool {
    if (which emacsclient | is-empty) { return false }
    let elisp = $file | str replace --all '\' '\\' | str replace --all '"' '\"'
    # -a false: never start a daemon from a pdf click ('' would start one when none runs)
    let open = ask timeout $ASK_TIMEOUT_S emacsclient -a "false" -e $"\(if \(get-file-buffer \"($elisp)\"\) t nil\)"
    if $open.exit_code != 0 or ($open.stdout | str trim) != "t" { return false }
    let opened = ask timeout $OPEN_TIMEOUT_S emacsclient -a "false" -n $"+($line):($column)" $file
    if $opened.exit_code != 0 { return false }
    ask timeout $ASK_TIMEOUT_S emacsclient -a "false" -e "(select-frame-set-input-focus (selected-frame))" | ignore
    true
}

# Sioyek's inverse search: move the nvim or emacs that has <file> open to <line>.
def main [file: string, line: int, column: int = 0]: nothing -> nothing {
    let file = $file | path expand
    if (nvim-try $file $line $column) or (emacs-try $file $line $column) { return }
    let message = $"($file | path basename):($line) is not open in nvim or emacs"
    if (ask notify-send -a $NOTIFY_APP -u low -- "No editor has the source open" $message).exit_code != 0 {
        print --stderr $"synctex-edit: ($file):($line) is not open in any running nvim or emacs"
    }
    exit 1
}

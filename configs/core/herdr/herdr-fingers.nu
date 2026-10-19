#!/usr/bin/env -S nu --no-config-file

# tmux-fingers' builtin patterns, most specific first: a later match inside an earlier one is dropped
const PATTERNS = [
    r#'(?:https?://|git@|git://|ssh://|ftp://|file:///)[^\s()"'<>]+'#
    '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}'
    '\b\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\b'
    '(?:[.\w\-~$@]+)?(?:/[.\w\-@]+)+/?'
    '\b0x[0-9a-fA-F]+\b'
    '\b[0-9a-f]{7,128}\b'
    '\b[0-9]{4,}\b'
]
const FZF_ARGS = [
    --prompt "> " --border none --no-scrollbar --pointer " " --marker " " --gutter " " --no-sort
    --color "fg:-1,bg:-1,fg+:0,bg+:12,hl:12,hl+:0,info:11,prompt:10,gutter:-1"
    --bind "ctrl-o:execute-silent(setsid -f xdg-open {} >/dev/null 2>&1)+abort"
]

def main []: nothing -> nothing {
    let pane = $env.HERDR_ACTIVE_PANE_ID? | default ""
    if $pane == "" { error make {msg: "HERDR_ACTIVE_PANE_ID unset: run from a herdr key command"} }
    let text = ^herdr pane read $pane --source visible
    let tokens = $text | lines | reverse
        | each {|line| $PATTERNS | each {|p| $line | parse --regex $"\(?<m>($p)\)" | get m } | flatten }
        | flatten
        | reduce --fold [] {|t, kept| if ($kept | any { str contains $t }) { $kept } else { $kept | append $t } }
    if ($tokens | is-empty) { return }
    let picked = try { $tokens | str join "\n" | ^fzf ...$FZF_ARGS } catch { "" } | str trim --right
    if $picked == "" { return }
    $picked | ^wl-copy --trim-newline
}

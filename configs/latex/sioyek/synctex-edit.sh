#!/usr/bin/env bash
: "${DOTFILES:=$HOME/projects/arch-dotfiles}"
# backward search (pdf spot -> latex source) for sioyek's inverse_search_command and zathura's synctex-editor-command, into whichever editor already has the file open, set in the viewers' own config so it works regardless of who launched them; usage: synctex-edit <file> <line> [column]

set -uo pipefail

file=${1:-}
line=${2:-}
column=${3:-0}

[[ -n "$file" && -n "$line" ]] || {
    echo "usage: synctex-edit <file> <line> [column]" >&2
    exit 1
}
[[ "$line" =~ ^[0-9]+$ && "$column" =~ ^[0-9]+$ ]] || {
    echo "synctex-edit: line and column must be numeric" >&2
    exit 1
}

# the viewer hands out the path synctex recorded, which is relative to the build dir for an out-of-tree build
file=$(readlink -f "$file" 2>/dev/null || printf '%s' "$file")
[[ -n "$column" ]] || column=0

# lua-escape nothing: the path goes through vim's own quoting below
esc_file=${file//\'/\'\'}
elisp_file=${file//\\/\\\\}
elisp_file=${elisp_file//\"/\\\"}

try_nvim() {
    command -v nvim >/dev/null 2>&1 || return 1

    local sockets=() sock result
    # vimtex keeps its own list, which outlives $XDG_RUNTIME_DIR entries from a crashed instance
    local log="${XDG_CACHE_HOME:-$HOME/.cache}/vimtex/nvim_servernames.log"
    [[ -r "$log" ]] && mapfile -t sockets <"$log"
    shopt -s nullglob
    sockets+=("${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"/nvim.*)
    shopt -u nullglob

    local seen=()
    for sock in "${sockets[@]}"; do
        [[ -S "$sock" ]] || continue
        [[ " ${seen[*]-} " == *" $sock "* ]] && continue
        seen+=("$sock")

        # vimtex answers <0 when no project in that instance owns the file, so every nvim can be asked safely
        result=$(timeout 2 nvim --server "$sock" --remote-expr \
            "vimtex#view#inverse_search($line, '$esc_file', $column)" 2>/dev/null) || continue
        [[ "$result" == -* ]] && continue
        return 0
    done
    return 1
}

try_emacs() {
    command -v emacsclient >/dev/null 2>&1 || return 1

    # -a '': never start a daemon from a pdf click
    local open
    open=$(timeout 2 emacsclient -a '' -e "(if (get-file-buffer \"$elisp_file\") t nil)" 2>/dev/null) || return 1
    [[ "$open" == t ]] || return 1

    timeout 5 emacsclient -a '' -n "+${line}:${column}" "$file" >/dev/null 2>&1 || return 1
    # raise the frame; harmless when the compositor refuses the activation
    timeout 2 emacsclient -a '' -e '(select-frame-set-input-focus (selected-frame))' >/dev/null 2>&1
    return 0
}

try_nvim && exit 0
try_emacs && exit 0

# nothing had it open: say so rather than guessing which editor to start
"$DOTFILES/scripts/lib/notification-send.sh" "synctex" "$(basename "$file"):$line is not open in nvim or emacs" 2>/dev/null \
    || echo "synctex-edit: $file:$line is not open in any running nvim or emacs" >&2
exit 1

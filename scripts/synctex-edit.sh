#!/usr/bin/env bash
# zathura's synctex-editor-command: jump from a spot in the pdf back to the latex source.
#
# usage: synctex-edit <file> <line> [column]
#
# Forward search (source -> pdf) has always worked because vimtex and AUCTeX pass --synctex-forward when they
# launch the viewer. Backward search did not: zathura only knows an editor command when it was started with
# -x, so it worked from a vimtex-launched viewer and from nowhere else -- not from latexmk's $pdf_previewer,
# not from a zathura opened by hand, not from a second pdf opened in the same instance. Setting
# synctex-editor-command in zathurarc to this script makes it work regardless of who started zathura.
#
# The jump goes to whichever editor already has the file open, so clicking in the pdf never spawns a second
# copy of a buffer that is already in front of you.

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

# zathura hands out the path synctex recorded, which is relative to the build dir for an out-of-tree build
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
if command -v notification-send >/dev/null 2>&1; then
    notification-send "synctex" "$(basename "$file"):$line is not open in nvim or emacs"
else
    echo "synctex-edit: $file:$line is not open in any running nvim or emacs" >&2
fi
exit 1

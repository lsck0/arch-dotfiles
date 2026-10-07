#!/usr/bin/env bash

vendor="$HOME/.cache/nushell"
link_into "$HOME/.config/nushell" env.nu config.nu
mkdir -p "$vendor" "$HOME/.cache/wal"

# vendor init scripts; empty when the tool is missing, config.nu sources them unconditionally
gen() {
    local out="$vendor/$1"; shift
    if command -v "$1" >/dev/null 2>&1 && "$@" > "$out.tmp" 2>/dev/null; then
        mv -f "$out.tmp" "$out"
    else
        rm -f "$out.tmp"
        : > "$out"
    fi
}
gen starship.nu starship init nu
gen zoxide.nu zoxide init nushell

[[ -e "$HOME/.cache/wal/colors-nushell.nu" ]] || : > "$HOME/.cache/wal/colors-nushell.nu"
ln -sfn "$HOME/.cache/wal/colors-nushell.nu" "$vendor/wal.nu"

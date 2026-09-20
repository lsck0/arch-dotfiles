#!/usr/bin/env bash
cd "$(dirname "$(readlink -f "$0")")" || exit 1

if ! command -v nu >/dev/null 2>&1; then
    exit 0
fi

set -ex

mkdir -p "$HOME/.config/nushell" "$HOME/.cache/nushell"
ln -sfn "${PWD}/env.nu" "$HOME/.config/nushell/env.nu"
ln -sfn "${PWD}/config.nu" "$HOME/.config/nushell/config.nu"

vendor="$HOME/.cache/nushell"
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
gen mise.nu mise activate nu

mkdir -p "$HOME/.cache/wal"
[[ -e "$HOME/.cache/wal/colors-nushell.nu" ]] || : > "$HOME/.cache/wal/colors-nushell.nu"
ln -sfn "$HOME/.cache/wal/colors-nushell.nu" "$vendor/wal.nu"

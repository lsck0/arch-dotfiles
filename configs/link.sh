#!/usr/bin/env bash

set -ex

# helper: link only if the target binary is on PATH
maybe_link() {
    local binary="$1" src="$2" dest="$3"
    if ! command -v "$binary" >/dev/null 2>&1; then
        return 0
    fi

    if [[ -d "$src" ]]; then
        ln -sf "$src" "$dest"
    elif [[ -f "$src" ]]; then
        mkdir -p "$(dirname "$dest")"
        ln -sf "$src" "$dest"
    fi
}

maybe_link btop    "${PWD}/btop"    "${HOME}/.config/btop"
maybe_link emacs   "${PWD}/emacs"   "${HOME}/.config/emacs"
maybe_link ghostty "${PWD}/ghostty" "${HOME}/.config/ghostty"
maybe_link nsxiv   "${PWD}/nsxiv"   "${HOME}/.config/nsxiv"
maybe_link nvim    "${PWD}/nvim"    "${HOME}/.config/nvim"
maybe_link wlogout "${PWD}/wlogout" "${HOME}/.config/wlogout"
maybe_link zed     "${PWD}/zed"     "${HOME}/.config/zed"

# hyprland family
if command -v Hyprland >/dev/null 2>&1; then
    ln -sf "${PWD}/hyprland" "${HOME}/.config/hypr"
    ln -sf "${PWD}/hyprland/hyprlock-launch.sh" "${HOME}/.config/hypr/hyprlock-launch.sh"
    ln -sf "${PWD}/uwsm" "${HOME}/.config/uwsm"
fi

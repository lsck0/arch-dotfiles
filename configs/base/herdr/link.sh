#!/usr/bin/env bash
cd "$(dirname "$(readlink -f "$0")")" || exit 1

set -e

mkdir -p "${HOME}/.config/herdr"
ln -sfn "${PWD}/config.toml" "${HOME}/.config/herdr/config.toml"

# command on PATH, invoked bare by tmux/herdr/nvim/viewers
mkdir -p "$HOME/.local/bin"
ln -sfn "$DOTFILES/configs/base/herdr/herdr-open.sh" "$HOME/.local/bin/herdr-open"

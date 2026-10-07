#!/usr/bin/env bash
cd "$(dirname "$(readlink -f "$0")")" || exit 1

set -e

mkdir -p "${HOME}/.config/yazi"

ln -sfn "${PWD}/yazi.toml" "${HOME}/.config/yazi/yazi.toml"
ln -sfn "${PWD}/keymap.toml" "${HOME}/.config/yazi/keymap.toml"

# theme.toml is rendered by wallust
ln -sfn "${HOME}/.cache/wal/colors-yazi.toml" "${HOME}/.config/yazi/theme.toml"

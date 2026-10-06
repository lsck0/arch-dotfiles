#!/usr/bin/env bash
cd "$(dirname "$(readlink -f "$0")")" || exit 1

source $DOTFILES/scripts/lib/personal.sh
is_personal || exit 0

set -e

mkdir -p "$HOME/.config/bugwarrior" "$HOME/.local/state/bugwarrior"
ln -sfn "${PWD}/bugwarrior.toml" "$HOME/.config/bugwarrior/bugwarrior.toml"

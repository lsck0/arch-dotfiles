#!/usr/bin/env bash
cd "$(dirname "$(readlink -f "$0")")" || exit 1

if ! command -v bugwarrior >/dev/null 2>&1; then
    exit 0
fi

set -ex

mkdir -p "$HOME/.config/bugwarrior" "$HOME/.local/state/bugwarrior"
ln -sfn "${PWD}/bugwarrior.toml" "$HOME/.config/bugwarrior/bugwarrior.toml"

#!/usr/bin/env bash
cd "$(dirname "$(readlink -f "$0")")" || exit 1

if ! command -v lazygit >/dev/null 2>&1; then
    exit 0
fi

set -ex

mkdir -p "$HOME/.config/lazygit"
ln -sf "${PWD}/config.yml" "$HOME/.config/lazygit/config.yml"

#!/usr/bin/env bash
cd "$(dirname "$(readlink -f "$0")")" || exit 1

if ! command -v nvim >/dev/null 2>&1; then
    exit 0
fi

set -e

# plugins, lsp tools and parsers install themselves on first launch (lazy restores to
# lazy-lock.json, mason-tool-installer run_on_start, treesitter VimEnter), not here
ln -sfn "${PWD}" "$HOME/.config/nvim"

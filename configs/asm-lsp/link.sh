#!/usr/bin/env bash
cd "$(dirname "$(readlink -f "$0")")" || exit 1

set -ex

# asm-lsp reads its global config from $XDG_CONFIG_HOME/asm-lsp/.asm-lsp.toml (see `asm-lsp info`).
mkdir -p "${HOME}/.config/asm-lsp"
ln -sfn "${PWD}/.asm-lsp.toml" "${HOME}/.config/asm-lsp/.asm-lsp.toml"

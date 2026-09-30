#!/usr/bin/env bash
cd "$(dirname "$(readlink -f "$0")")" || exit 1

set -e

mkdir -p "${HOME}/.config/asm-lsp"
ln -sfn "${PWD}/.asm-lsp.toml" "${HOME}/.config/asm-lsp/.asm-lsp.toml"

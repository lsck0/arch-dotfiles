#!/usr/bin/env bash

set -ex

# asm-lsp reads its global config from $XDG_CONFIG_HOME/asm-lsp/.asm-lsp.toml
# (see `asm-lsp info`). A project-local .asm-lsp.toml still overrides this.
mkdir -p "${HOME}/.config/asm-lsp"
ln -sfn "${PWD}/.asm-lsp.toml" "${HOME}/.config/asm-lsp/.asm-lsp.toml"

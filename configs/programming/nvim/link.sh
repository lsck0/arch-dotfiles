#!/usr/bin/env bash

# plugins, lsp tools and parsers install themselves on first launch (lazy restores to
# lazy-lock.json, mason-tool-installer run_on_start, treesitter VimEnter), not here
link_dir "${PWD}" "$HOME/.config/nvim"

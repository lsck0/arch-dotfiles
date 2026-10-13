#!/usr/bin/env bash

link_dir "${PWD}" "$HOME/.config/nvim"

# plugins, lsp tools and parsers install now instead of on first launch: lazy restores to lazy-lock.json, then the
# blocking variants of the treesitter and mason-tool-installer startup installs. each skips what is already there, so
# a rerun only adds what is new or was offline before
if command -v nvim >/dev/null 2>&1; then
    if ! nvim --headless "+Lazy! restore" "+TSInstallSync" "+MasonToolsInstallSync" "+qa" \
        >/dev/null 2>"${PWD}/prefetch.log"; then
        echo "nvim: installing its plugins, parsers or lsp tools failed, see ${PWD}/prefetch.log; retried on the next run" >&2
    fi
fi

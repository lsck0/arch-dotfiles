#!/usr/bin/env bash

if ! command -v codium >/dev/null 2>&1 && ! command -v code >/dev/null 2>&1; then
    exit 0
fi

link_into "${HOME}/.config/VSCodium/User" settings.json keybindings.json

# settings.json uses vim mode
for bin in codium code; do
    if command -v "$bin" >/dev/null 2>&1; then
        "$bin" --install-extension vscodevim.vim >/dev/null
        break
    fi
done

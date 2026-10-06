#!/usr/bin/env bash
cd "$(dirname "$(readlink -f "$0")")" || exit 1

if ! command -v codium >/dev/null 2>&1 && ! command -v code >/dev/null 2>&1; then
    exit 0
fi

set -e

mkdir -p "${HOME}/.config/VSCodium/User"

ln -sfn "${PWD}/settings.json" "${HOME}/.config/VSCodium/User/settings.json"
ln -sfn "${PWD}/keybindings.json" "${HOME}/.config/VSCodium/User/keybindings.json"

# settings.json uses vim mode
for bin in codium code; do
    if command -v "$bin" >/dev/null 2>&1; then
        "$bin" --install-extension vscodevim.vim >/dev/null
        break
    fi
done

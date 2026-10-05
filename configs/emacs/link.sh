#!/usr/bin/env bash
cd "$(dirname "$(readlink -f "$0")")" || exit 1

if ! command -v emacs >/dev/null 2>&1; then
    exit 0
fi

set -e

# packages install themselves on first launch (use-package-always-ensure), not here
ln -sfn "${PWD}" "$HOME/.config/emacs"

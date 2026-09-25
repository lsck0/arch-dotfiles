#!/usr/bin/env bash
cd "$(dirname "$(readlink -f "$0")")" || exit 1

if ! command -v latexmk >/dev/null 2>&1; then
    exit 0
fi

set -ex

ln -sfn "${PWD}/latexmkrc" "$HOME/.latexmkrc"

#!/usr/bin/env bash

if ! command -v emacs >/dev/null 2>&1; then
    exit 0
fi

set -ex

ln -sfn "${PWD}" "$HOME/.config/emacs"

emacs --batch \
    -l "${HOME}/.config/emacs/early-init.el" \
    -l "${HOME}/.config/emacs/init.el" \
    --eval '(princ "emacs: package bootstrap complete\n")'

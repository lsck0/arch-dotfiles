#!/usr/bin/env bash
# Symlinks this repo's Emacs config into ~/.config/emacs, then bootstraps
# every use-package :ensure package non-interactively so a fresh install
# has a working Emacs on first launch (matches nvim's lazy.nvim bootstrap,
# which self-installs on first startup already -- Emacs has no equivalent
# automatic mechanism, package.el needs an explicit batch pass).
if ! command -v emacs >/dev/null 2>&1; then
    exit 0
fi

set -ex

mkdir -p "${HOME}/.config"
ln -sfn "${PWD}" "${HOME}/.config/emacs"

# --batch does NOT load early-init.el on its own -- both must be -l'd
# explicitly or config relying on early-init state (fonts, frame params)
# errors with a spurious void-variable. init.el's own package-refresh +
# every use-package form's :ensure t does the actual installing; this call
# just needs to run init.el all the way through once.
emacs --batch \
    -l "${HOME}/.config/emacs/early-init.el" \
    -l "${HOME}/.config/emacs/init.el" \
    --eval '(princ "emacs: package bootstrap complete\n")'

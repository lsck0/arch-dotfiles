#!/usr/bin/env bash

set -ex

# doomemacs clones and installs Doom Emacs. Guard on `git` and `emacs` so a
# rerun on a machine without either skips cleanly instead of `set -e`
# aborting.
if ! command -v git >/dev/null 2>&1 || ! command -v emacs >/dev/null 2>&1; then
    echo "configs/doomemacs/link.sh: git/emacs not installed, skipping" >&2
    exit 0
fi

export EMACSDIR="${HOME}/.config/doom-emacs"

rm -rf "$EMACSDIR"
git clone https://github.com/doomemacs/doomemacs "$EMACSDIR" --depth 1
"$EMACSDIR/bin/doom" install --aot --force

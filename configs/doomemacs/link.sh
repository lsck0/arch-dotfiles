#!/usr/bin/env bash

set -ex

export EMACSDIR="${HOME}/.config/doom-emacs"

rm -rf "$EMACSDIR"
git clone https://github.com/doomemacs/doomemacs "$EMACSDIR" --depth 1
"$EMACSDIR/bin/doom" install --aot --force

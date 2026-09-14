#!/usr/bin/env bash

# bookokrat rewrites its whole settings file (atomic write+rename) on every
# save (theme change, panel resize, etc.), which replaces a symlink here
# with a plain file. So this only seeds the file once; after that, live
# state (theme, panel width, synctex_editor) is personal and not tracked.
mkdir -p "$HOME/.config/bookokrat"
if [ ! -e "$HOME/.config/bookokrat/config.yaml" ]; then
    cp -v "$PWD/config.yaml" "$HOME/.config/bookokrat/config.yaml"
fi

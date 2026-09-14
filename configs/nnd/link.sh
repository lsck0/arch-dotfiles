#!/usr/bin/env bash
# nnd (linux debugger) config. No theming support exists upstream --
# `nnd --help-misc` states outright: "No customization of colors. Dark theme
# only." -- so this only symlinks keybinding/settings overrides into ~/.nnd/,
# same pattern as configs/gdb and configs/cgdb.

if ! command -v nnd >/dev/null 2>&1; then
    exit 0
fi

set -ex

mkdir -p "${HOME}/.nnd"

ln -sf "${PWD}/keys" "${HOME}/.nnd/keys"

#!/usr/bin/env bash
cd "$(dirname "$(readlink -f "$0")")" || exit 1

if ! command -v zathura >/dev/null 2>&1; then
    exit 0
fi

set -ex

mkdir -p "$HOME/.config/zathura" "$HOME/.cache/wal"
ln -sfn "${PWD}/zathurarc" "$HOME/.config/zathura/zathurarc"

# zathurarc's `include` is resolved next to the config file and does not expand
# ~, so the wallust palette is reached through a link rather than a path. The
# target is created empty when wallust has not run yet: a missing include is a
# warning on every start.
[[ -e "$HOME/.cache/wal/colors-zathura" ]] || : > "$HOME/.cache/wal/colors-zathura"
ln -sfn "$HOME/.cache/wal/colors-zathura" "$HOME/.config/zathura/colors-zathura"

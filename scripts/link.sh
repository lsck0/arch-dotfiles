#!/usr/bin/env bash
# Symlink every scripts/*.sh and *.py into ~/.local/bin; user scripts stay out of root's secure_path.

set -e

shopt -s nullglob

mkdir -p "$HOME/.local/bin"
for script in *.sh *.py; do
    [[ "$script" == "link.sh" ]] && continue
    ln -sfn "$PWD/$script" "$HOME/.local/bin/${script%.*}"
done

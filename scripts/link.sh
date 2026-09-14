#!/usr/bin/env bash

set -ex

# Globs, not `ls`: an empty match makes `ls` exit non-zero and take the whole
# script down under `set -e`.
shopt -s nullglob

for script in *.sh; do
    [[ "$script" == "link.sh" ]] && continue
    sudo ln -sfn "$PWD/$script" "/usr/local/bin/$(basename "$script" .sh)"
done

for script in *.py; do
    sudo ln -sfn "$PWD/$script" "/usr/local/bin/$(basename "$script" .py)"
done

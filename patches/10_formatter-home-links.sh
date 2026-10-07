#!/usr/bin/env bash
# drop the formatter configs formatting/link.sh linked into $HOME, which styled every third-party repo; conform now passes them only to projects without their own

set -euo pipefail

CHECKOUT=$(dirname "$(dirname "$(readlink -f "$0")")")

for link in ~/.clang-format ~/.stylua.toml ~/.prettierrc ~/.editorconfig ~/.rustfmt.toml ~/.config/ruff/ruff.toml; do
    if [[ "$(readlink "$link")" == "$CHECKOUT"/* ]]; then rm -f "$link"; fi
done

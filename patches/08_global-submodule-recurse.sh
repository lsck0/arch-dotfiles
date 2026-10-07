#!/usr/bin/env bash
# drop the global submodule.recurse true that base/git/link.sh used to set; the zsh clone wrapper covers cloning

set -euo pipefail

[[ "$(git config --global --type bool --get submodule.recurse || true)" == true ]] || exit 0
git config --global --unset submodule.recurse

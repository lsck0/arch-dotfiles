# shellcheck shell=bash
# $DOTFILES: the repo root, the one anchor every script and link.sh builds absolute paths from.
# set by install.sh/config.sh and the login env; this git/path fallback covers a standalone run.
: "${DOTFILES:=$(cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")/../.." && pwd)}"
export DOTFILES

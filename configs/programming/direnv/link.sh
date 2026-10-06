#!/usr/bin/env bash

# install.sh puts devenv in the nix profile, which may not be on PATH yet
DEVENV="$(command -v devenv || echo "${HOME}/.nix-profile/bin/devenv")"
if ! command -v direnv >/dev/null 2>&1 || [[ ! -x "$DEVENV" ]]; then
    exit 0
fi

set -e

mkdir -p "${HOME}/.config/direnv"
"$DEVENV" direnvrc > "${HOME}/.config/direnv/direnvrc"

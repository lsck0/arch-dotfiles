#!/usr/bin/env bash

if ! command -v direnv >/dev/null 2>&1; then
    exit 0
fi

set -ex

mkdir -p "${HOME}/.config/direnv"

# install.sh adds devenv through nix profile in this same run, before PATH has the profile
DEVENV="$(command -v devenv || echo "${HOME}/.nix-profile/bin/devenv")"
"$DEVENV" direnvrc > "${HOME}/.config/direnv/direnvrc"

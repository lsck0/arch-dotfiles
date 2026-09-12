#!/usr/bin/env bash

if ! command -v starship >/dev/null 2>&1; then
    exit 0
fi

set -ex

ln -sf ${PWD}/starship.toml ${HOME}/.config/starship.toml

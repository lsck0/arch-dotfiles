#!/usr/bin/env bash

if ! command -v herdr >/dev/null 2>&1; then
    exit 0
fi

set -ex

mkdir -p ${HOME}/.config/herdr

ln -sf ${PWD}/config.toml ${HOME}/.config/herdr/config.toml

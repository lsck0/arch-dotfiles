#!/usr/bin/env bash

if ! command -v mise >/dev/null 2>&1; then
    exit 0
fi

set -ex

ln -sf ${PWD}/mise.toml ${HOME}/.mise.toml

mise trust ${HOME}/.mise.toml

#!/usr/bin/env bash
cd "$(dirname "$(readlink -f "$0")")" || exit 1

if ! command -v mise >/dev/null 2>&1; then
    exit 0
fi

set -ex

ln -sfn ${PWD}/mise.toml ${HOME}/.mise.toml

mise trust ${HOME}/.mise.toml

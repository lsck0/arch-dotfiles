#!/usr/bin/env bash

if ! command -v nix >/dev/null 2>&1; then
    exit 0
fi

set -ex

ln -sfn "${PWD}" "$HOME/.config/nix"

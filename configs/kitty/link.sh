#!/usr/bin/env bash

if ! command -v kitty >/dev/null 2>&1; then
    exit 0
fi

set -ex

mkdir -p ${HOME}/.config/kitty

ln -sf ${PWD}/kitty.conf ${HOME}/.config/kitty/kitty.conf

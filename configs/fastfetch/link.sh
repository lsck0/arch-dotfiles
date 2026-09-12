#!/usr/bin/env bash

if ! command -v fastfetch >/dev/null 2>&1; then
    exit 0
fi

set -ex

mkdir -p ${HOME}/.config/fastfetch

ln -sf ${PWD}/fastfetch.jsonc ${HOME}/.config/fastfetch/config.jsonc

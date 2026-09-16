#!/usr/bin/env bash
cd "$(dirname "$(readlink -f "$0")")" || exit 1

if ! command -v kitty >/dev/null 2>&1; then
    exit 0
fi

set -ex

mkdir -p ${HOME}/.config/kitty

ln -sfn ${PWD}/kitty.conf ${HOME}/.config/kitty/kitty.conf

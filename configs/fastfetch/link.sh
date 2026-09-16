#!/usr/bin/env bash
cd "$(dirname "$(readlink -f "$0")")" || exit 1

if ! command -v fastfetch >/dev/null 2>&1; then
    exit 0
fi

set -ex

mkdir -p ${HOME}/.config/fastfetch

ln -sfn ${PWD}/fastfetch.jsonc ${HOME}/.config/fastfetch/config.jsonc

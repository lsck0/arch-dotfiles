#!/usr/bin/env bash
cd "$(dirname "$(readlink -f "$0")")" || exit 1

if ! command -v herdr >/dev/null 2>&1; then
    exit 0
fi

set -ex

mkdir -p ${HOME}/.config/herdr

ln -sfn ${PWD}/config.toml ${HOME}/.config/herdr/config.toml

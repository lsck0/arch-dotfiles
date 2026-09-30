#!/usr/bin/env bash
cd "$(dirname "$(readlink -f "$0")")" || exit 1

if ! command -v easyeffects >/dev/null 2>&1; then
    exit 0
fi

set -e

# presets saved in the app land in the repo
mkdir -p "${HOME}/.config/easyeffects"
ln -sfn "${PWD}/input" "${HOME}/.config/easyeffects/input"
ln -sfn "${PWD}/output" "${HOME}/.config/easyeffects/output"

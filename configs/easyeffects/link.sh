#!/usr/bin/env bash
cd "$(dirname "$(readlink -f "$0")")" || exit 1

if ! command -v easyeffects >/dev/null 2>&1; then
    exit 0
fi

set -ex

# Track presets in the repo: EasyEffects reads/writes input/ (mic) and output/
# (playback) preset JSON here. Empty for now; save a preset in the app and it
# lands in these dirs, then commit it.
mkdir -p "${HOME}/.config/easyeffects"
ln -sfn "${PWD}/input" "${HOME}/.config/easyeffects/input"
ln -sfn "${PWD}/output" "${HOME}/.config/easyeffects/output"

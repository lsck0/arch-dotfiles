#!/usr/bin/env bash

if ! command -v oomox >/dev/null 2>&1; then
    exit 0
fi

set -ex

mkdir -p ${HOME}/.config/oomox/export_config/

ln -sf ${PWD}/multi_export_oodwaita.json ${HOME}/.config/oomox/export_config/
ln -sf ${PWD}/multi_export_oomox_classic.json ${HOME}/.config/oomox/export_config/

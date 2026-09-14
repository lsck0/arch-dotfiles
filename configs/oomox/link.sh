#!/usr/bin/env bash

if ! command -v themix-multi-export >/dev/null 2>&1; then
    exit 0
fi

set -ex

mkdir -p ${HOME}/.config/oomox/export_config/

ln -sfn ${PWD}/multi_export_oodwaita.json ${HOME}/.config/oomox/export_config/multi_export_oodwaita.json
ln -sfn ${PWD}/multi_export_oomox_classic.json ${HOME}/.config/oomox/export_config/multi_export_oomox_classic.json

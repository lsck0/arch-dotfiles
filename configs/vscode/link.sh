#!/usr/bin/env bash

if ! command -v codium >/dev/null 2>&1 && ! command -v code >/dev/null 2>&1; then
    exit 0
fi

set -ex

mkdir -p ${HOME}/.config/VSCodium/User

ln -sf ${PWD}/settings.json ${HOME}/.config/VSCodium/User/settings.json

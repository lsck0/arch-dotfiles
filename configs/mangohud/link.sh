#!/usr/bin/env bash
cd "$(dirname "$(readlink -f "$0")")" || exit 1

if ! command -v mangohud >/dev/null 2>&1; then
    exit 0
fi

set -e

mkdir -p "${HOME}/.config/MangoHud"
ln -sfn "${PWD}/MangoHud.conf" "${HOME}/.config/MangoHud/MangoHud.conf"

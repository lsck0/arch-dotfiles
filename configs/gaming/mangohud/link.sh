#!/usr/bin/env bash
cd "$(dirname "$(readlink -f "$0")")" || exit 1

set -e

mkdir -p "${HOME}/.config/MangoHud"
ln -sfn "${PWD}/MangoHud.conf" "${HOME}/.config/MangoHud/MangoHud.conf"

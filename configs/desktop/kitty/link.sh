#!/usr/bin/env bash
cd "$(dirname "$(readlink -f "$0")")" || exit 1

set -e

mkdir -p "${HOME}/.config/kitty"
ln -sfn "${PWD}/kitty.conf" "${HOME}/.config/kitty/kitty.conf"

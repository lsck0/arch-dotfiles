#!/usr/bin/env bash
cd "$(dirname "$(readlink -f "$0")")" || exit 1

set -e

mkdir -p "${HOME}/.config/fastfetch"
ln -sfn "${PWD}/fastfetch.jsonc" "${HOME}/.config/fastfetch/config.jsonc"

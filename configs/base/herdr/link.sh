#!/usr/bin/env bash
cd "$(dirname "$(readlink -f "$0")")" || exit 1

set -e

mkdir -p "${HOME}/.config/herdr"
ln -sfn "${PWD}/config.toml" "${HOME}/.config/herdr/config.toml"

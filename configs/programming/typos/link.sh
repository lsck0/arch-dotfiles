#!/usr/bin/env bash
cd "$(dirname "$(readlink -f "$0")")" || exit 1

set -e

mkdir -p "${HOME}/.config/typos"
ln -sfn "${PWD}/typos.toml" "${HOME}/.config/typos/typos.toml"

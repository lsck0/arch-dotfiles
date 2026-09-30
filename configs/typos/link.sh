#!/usr/bin/env bash
cd "$(dirname "$(readlink -f "$0")")" || exit 1

if ! command -v typos >/dev/null 2>&1; then
    exit 0
fi

set -ex

mkdir -p "${HOME}/.config/typos"
ln -sfn "${PWD}/typos.toml" "${HOME}/.config/typos/typos.toml"

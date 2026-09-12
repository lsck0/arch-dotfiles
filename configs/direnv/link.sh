#!/usr/bin/env bash


if ! command -v devenv >/dev/null 2>&1; then
    exit 0
fi

set -ex

mkdir -p "${HOME}/.config/direnv"

devenv direnvrc > "${HOME}/.config/direnv/direnvrc"

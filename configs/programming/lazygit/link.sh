#!/usr/bin/env bash
cd "$(dirname "$(readlink -f "$0")")" || exit 1

set -e

mkdir -p "${HOME}/.config/lazygit"
ln -sfn "${PWD}/config.yml" "${HOME}/.config/lazygit/config.yml"

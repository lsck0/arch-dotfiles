#!/usr/bin/env bash
cd "$(dirname "$(readlink -f "$0")")" || exit 1

set -ex

mkdir -p "$HOME/.config/bookokrat"

if [ ! -e "$HOME/.config/bookokrat/config.yaml" ]; then
    cp -v "$PWD/config.yaml" "$HOME/.config/bookokrat/config.yaml"
fi

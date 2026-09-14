#!/usr/bin/env bash

set -ex

mkdir -p "$HOME/.config/bookokrat"

if [ ! -e "$HOME/.config/bookokrat/config.yaml" ]; then
    cp -v "$PWD/config.yaml" "$HOME/.config/bookokrat/config.yaml"
fi

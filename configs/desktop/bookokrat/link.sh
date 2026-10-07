#!/usr/bin/env bash

# a seed only: bookokrat writes its own state into this file
mkdir -p "$HOME/.config/bookokrat"
[[ -e "$HOME/.config/bookokrat/config.yaml" ]] || cp "$PWD/config.yaml" "$HOME/.config/bookokrat/config.yaml"

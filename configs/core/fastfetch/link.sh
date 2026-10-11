#!/usr/bin/env bash

mkdir -p "${HOME}/.config/fastfetch"
ln -sfn "${PWD}/fastfetch.jsonc" "${HOME}/.config/fastfetch/config.jsonc"

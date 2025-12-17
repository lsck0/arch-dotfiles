#!/usr/bin/env bash

set -ex

mkdir -p ${HOME}/.config/fastfetch
ln -sf ${PWD}/fastfetch.jsonc ${HOME}/.config/fastfetch/config.jsonc

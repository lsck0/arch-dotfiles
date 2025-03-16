#!/bin/env bash

set -ex

sudo mkdir -p ${HOME}/.config/fastfetch
sudo ln -sf ${PWD}/fastfetch.jsonc ${HOME}/.config/fastfetch/config.jsonc

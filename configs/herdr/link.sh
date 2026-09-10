#!/usr/bin/env bash

set -ex

mkdir -p ${HOME}/.config/herdr
ln -sf ${PWD}/config.toml ${HOME}/.config/herdr/config.toml

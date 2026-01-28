#!/usr/bin/env bash

set -ex

mkdir -p ${HOME}/.config/opencode
ln -sf ${PWD}/opencode.json ${HOME}/.config/opencode/

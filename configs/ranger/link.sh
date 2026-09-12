#!/usr/bin/env bash

if ! command -v ranger >/dev/null 2>&1; then
    exit 0
fi

set -ex

mkdir -p ${HOME}/.config/ranger

ln -sf ${PWD}/rc.conf ${HOME}/.config/ranger/rc.conf

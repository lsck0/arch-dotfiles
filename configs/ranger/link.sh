#!/usr/bin/env bash
cd "$(dirname "$(readlink -f "$0")")" || exit 1

if ! command -v ranger >/dev/null 2>&1; then
    exit 0
fi

set -ex

mkdir -p ${HOME}/.config/ranger

ln -sfn ${PWD}/rc.conf ${HOME}/.config/ranger/rc.conf

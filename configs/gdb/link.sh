#!/usr/bin/env bash

if ! command -v gdb >/dev/null 2>&1; then
    exit 0
fi

set -ex

ln -sfn ${PWD}/gdbinit ${HOME}/.gdbinit

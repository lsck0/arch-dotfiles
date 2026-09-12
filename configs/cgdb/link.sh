#!/usr/bin/env bash

if ! command -v cgdb >/dev/null 2>&1; then
    exit 0
fi

set -ex

mkdir -p ${HOME}/.cgdb

ln -sf ${PWD}/cgdbrc ${HOME}/.cgdb/cgdbrc

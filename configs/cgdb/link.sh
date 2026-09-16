#!/usr/bin/env bash
cd "$(dirname "$(readlink -f "$0")")" || exit 1

if ! command -v cgdb >/dev/null 2>&1; then
    exit 0
fi

set -ex

mkdir -p ${HOME}/.cgdb

ln -sfn ${PWD}/cgdbrc ${HOME}/.cgdb/cgdbrc

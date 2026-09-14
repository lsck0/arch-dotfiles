#!/usr/bin/env bash

if ! command -v nnd >/dev/null 2>&1; then
    exit 0
fi

set -ex

mkdir -p "${HOME}/.nnd"

ln -sfn "${PWD}/keys" "${HOME}/.nnd/keys"

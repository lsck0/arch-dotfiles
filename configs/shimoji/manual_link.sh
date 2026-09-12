#!/usr/bin/env bash

if ! command -v shimejictl >/dev/null 2>&1; then
    exit 0
fi

set -ex

ls *.wlshm | xargs -I {} shimejictl import {}

shimejictl config set BREEDING false

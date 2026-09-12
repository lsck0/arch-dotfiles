#!/usr/bin/env bash

if ! command -v cargo >/dev/null 2>&1; then
    exit 0
fi

set -ex

cargo kani setup

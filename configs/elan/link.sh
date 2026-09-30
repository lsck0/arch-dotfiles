#!/usr/bin/env bash

if ! command -v elan >/dev/null 2>&1; then
    exit 0
fi

set -e

/usr/bin/elan default nightly

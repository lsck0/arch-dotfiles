#!/usr/bin/env bash


if ! command -v elan >/dev/null 2>&1; then
    exit 0
fi

set -ex

/usr/bin/elan install nightly
/usr/bin/elan default nightly

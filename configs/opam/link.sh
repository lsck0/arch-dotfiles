#!/usr/bin/env bash

if ! command -v opam >/dev/null 2>&1; then
    exit 0
fi

set -e

opam init --no-setup

#!/usr/bin/env bash

if ! command -v git >/dev/null 2>&1 || ! command -v cargo >/dev/null 2>&1; then
    exit 0
fi

set -ex

git clone https://github.com/flux-rs/flux
pushd flux
cargo xtask install
popd
rm -rf flux

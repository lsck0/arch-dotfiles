#!/usr/bin/env bash

set -ex

git clone https://github.com/flux-rs/flux
pushd flux
cargo xtask install
popd
rm -rf flux

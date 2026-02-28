#!/usr/bin/env bash

set -ex

git clone https://github.com/ucsd-progsys/liquid-fixpoint.git
pushd liquid-fixpoint
stack install
popd
rm -rf liquid-fixpoint

git clone https://github.com/flux-rs/flux
pushd flux
cargo xtask install
popd
rm -rf flux

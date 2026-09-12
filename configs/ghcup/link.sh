#!/usr/bin/env bash

if ! command -v ghcup >/dev/null 2>&1; then
    exit 0
fi

set -ex

/usr/bin/ghcup install ghc
/usr/bin/ghcup install cabal
/usr/bin/ghcup install hls
/usr/bin/ghcup install stack

git clone https://github.com/ucsd-progsys/liquid-fixpoint.git
pushd liquid-fixpoint
~/.ghcup/bin/stack install
popd
rm -rf liquid-fixpoint

#!/usr/bin/env bash
cd "$(dirname "$(readlink -f "$0")")" || exit 1

if ! command -v ghcup >/dev/null 2>&1; then
    exit 0
fi

set -ex

/usr/bin/ghcup install ghc
/usr/bin/ghcup install cabal
/usr/bin/ghcup install hls
/usr/bin/ghcup install stack

/usr/bin/ghcup set ghc
/usr/bin/ghcup set cabal
/usr/bin/ghcup set hls
/usr/bin/ghcup set stack

SRC="$(mktemp -d)"
trap 'rm -rf "$SRC"' EXIT

git clone https://github.com/ucsd-progsys/liquid-fixpoint.git "$SRC"
cd "$SRC"
~/.ghcup/bin/stack install

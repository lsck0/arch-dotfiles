#!/usr/bin/env bash
cd "$(dirname "$(readlink -f "$0")")" || exit 1

set -e

mkdir -p "${HOME}/.nnd"

ln -sfn "${PWD}/keys" "${HOME}/.nnd/keys"

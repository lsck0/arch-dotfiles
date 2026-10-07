#!/usr/bin/env bash
cd "$(dirname "$(readlink -f "$0")")" || exit 1

set -e

[[ -d "${HOME}/.kani/kani-$(cargo-kani --version | awk 'NR==1{print $4}')" ]] || cargo kani setup

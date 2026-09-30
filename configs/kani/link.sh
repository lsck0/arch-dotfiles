#!/usr/bin/env bash
cd "$(dirname "$(readlink -f "$0")")" || exit 1

GROUPS_STATE="$HOME/projects/arch-dotfiles/groups.conf"
if [[ ! -f "$GROUPS_STATE" ]] || ! grep -qx programming "$GROUPS_STATE"; then
    exit 0
fi

if ! command -v cargo-kani >/dev/null 2>&1; then
    exit 0
fi

set -ex

cargo kani setup

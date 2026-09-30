#!/usr/bin/env bash
cd "$(dirname "$(readlink -f "$0")")" || exit 1

GROUPS_STATE="$HOME/projects/arch-dotfiles/groups.conf"
if [[ ! -f "$GROUPS_STATE" ]] || ! grep -qx programming "$GROUPS_STATE"; then
    exit 0
fi

if ! command -v git >/dev/null 2>&1 || ! command -v cargo >/dev/null 2>&1; then
    exit 0
fi

set -ex

SRC="$(mktemp -d)"
trap 'rm -rf "$SRC"' EXIT

git clone https://github.com/flux-rs/flux "$SRC"
cd "$SRC"
cargo xtask install

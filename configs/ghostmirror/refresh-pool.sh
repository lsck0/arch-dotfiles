#!/usr/bin/env bash
# Rebuild the mirror pool from the upstream Arch mirrorlist.

set -euo pipefail

target=/etc/pacman.d/mirrorlist
tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT

ghostmirror \
    -l "$tmp" \
    -c Germany,France,Switzerland,Austria,Poland,Denmark,Netherlands \
    -L 30 \
    -S state,outofdate,morerecent,ping

# never install a truncated or empty list over a working one
count=$(grep -c '^Server' "$tmp" || true)
if [ "$count" -lt 10 ]; then
    echo "refusing to install mirrorlist with only $count servers" >&2
    exit 1
fi

# $target is a symlink into the dotfiles repo; redirect writes through it
cat "$tmp" >"$target"
echo "installed $count mirrors"

#!/usr/bin/env bash

set -euo pipefail

# krita's first start builds its resource db, a preview per installed font family: minutes over the configs/fonts set,
# long enough under the splash to look hung, and a second launch then waits on the same db. kritarunner builds it here
# instead, into a scratch home moved in once done, so an interrupted run never leaves a half-built db behind
DATA="${XDG_DATA_HOME:-$HOME/.local/share}/krita"

command -v kritarunner >/dev/null 2>&1 || exit 0
[[ -e "$DATA/resourcecache.sqlite" ]] && exit 0
# kritarunner needs a display; without one the first start builds it
[[ -n "${WAYLAND_DISPLAY:-}${DISPLAY:-}" ]] || exit 0

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

mkdir -p "$tmp/data" "$tmp/config"
XDG_DATA_HOME="$tmp/data" XDG_CONFIG_HOME="$tmp/config" PYTHONPATH="$PWD" timeout 900 kritarunner -s warm >/dev/null
[[ -s "$tmp/data/kritarunner/resourcecache.sqlite" ]] || { echo "krita: kritarunner built no resource db" >&2; exit 1; }
mkdir -p "$DATA"
cp -a "$tmp/data/kritarunner/." "$DATA/"

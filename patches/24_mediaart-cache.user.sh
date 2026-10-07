#!/usr/bin/env bash
# drop the album covers the media widget once cached on disk; covers now live in $XDG_RUNTIME_DIR and only from home
set -euo pipefail

rm -rf "${XDG_CACHE_HOME:-$HOME/.cache}/quickshell/mediaart"

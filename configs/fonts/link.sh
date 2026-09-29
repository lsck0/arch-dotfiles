#!/usr/bin/env bash
# vendored OFL fonts with no arch package
set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")"
dest="$HOME/.local/share/fonts"
mkdir -p "$dest"
for f in *.ttf *.otf; do
    [ -e "$f" ] || continue
    install -m644 "$f" "$dest/$f"
done
fc-cache -f "$dest" >/dev/null 2>&1 || true

#!/usr/bin/env bash
# Install repo-vendored fonts that have no Arch/AUR package (OFL, redistributable).
set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")"
dest="$HOME/.local/share/fonts"
mkdir -p "$dest"
for f in *.ttf *.otf; do
    [ -e "$f" ] || continue
    install -m644 "$f" "$dest/$f"
done
fc-cache -f "$dest" >/dev/null 2>&1 || true

#!/usr/bin/env bash

set -euo pipefail

# PhotoGIMP: photoshop shortcuts, tool layout and docks over gimp's own config. the release ships no checksum and a tag
# can be re-uploaded, so the archive is pinned by content; bump both constants together
PHOTOGIMP_VERSION=3.1
PHOTOGIMP_SHA256=bf0e1279870d40152beb3e702cf3e4e01a6892031a1ace5bc4a9b858894b584e
PHOTOGIMP_URL="https://github.com/Diolinux/PhotoGIMP/releases/download/${PHOTOGIMP_VERSION}/PhotoGIMP-linux.zip"

command -v gimp >/dev/null 2>&1 || exit 0

# the release targets GIMP/3.0, an installed 3.2 reads its own dir and only migrates 3.0 when that is still missing
gimp_version=$(gimp --version | grep -oE '[0-9]+\.[0-9]+' | head -1)
config="${HOME}/.config/GIMP/${gimp_version}"
# gimp rewrites these files itself, so they are seeded once per release (copies, not links) and then left to it
stamp="${config}/.photogimp-${PHOTOGIMP_VERSION}"
[[ -e "$stamp" ]] && exit 0

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

fetch_pinned "$PHOTOGIMP_URL" "$PHOTOGIMP_SHA256" "$tmp/photogimp.zip"
unzip -q "$tmp/photogimp.zip" -d "$tmp"
# only the gimp config: its .desktop runs the flatpak and renames the app. a file of gimp's own that photogimp replaces
# (shortcuts, docks, a person's tweaks) is preserved first, never overwritten
src="$tmp/PhotoGIMP-linux/.config/GIMP/3.0"
while IFS= read -r -d '' file; do
    dest="$config/${file#"$src"/}"
    if [[ -e "$dest" || -L "$dest" ]] && ! cmp -s "$file" "$dest"; then
        preserve_aside "$dest"
    fi
    mkdir -p "$(dirname "$dest")"
    cp -f "$file" "$dest"
done < <(find "$src" -type f -print0)
touch "$stamp"

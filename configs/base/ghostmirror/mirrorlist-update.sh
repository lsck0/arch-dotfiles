#!/usr/bin/env bash
# runs as root from ghostmirror*.service; ranks into a temp dir so a short list never replaces the current one

set -euo pipefail

TARGET=/etc/pacman.d/mirrorlist
COUNTRIES=Germany,France,Switzerland,Austria,Poland,Denmark,Netherlands
MIRRORS_MAX=30
# fewer servers means a failed fetch
MIRRORS_MIN=10

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT
out="$tmpdir/mirrorlist"

case "${1:-}" in
sort)
    ghostmirror -uml "$TARGET" "$out" -s light -S state,outofdate,morerecent,estimated,speed
    ;;
rebuild)
    ghostmirror -l "$out" -c "$COUNTRIES" -L "$MIRRORS_MAX" -S state,outofdate,morerecent,ping
    ;;
*)
    echo "usage: $(basename "$0") {sort|rebuild}" >&2
    exit 2
    ;;
esac

count=$(grep -c '^Server' "$out" || true)
if [[ "$count" -lt "$MIRRORS_MIN" ]]; then
    echo "mirrorlist-update: only $count servers, keeping the current list" >&2
    exit 1
fi

# homelab first (internal, authoritative), the ranked public mirrors are the away fallback
{
    echo "# homelab full mirror (10.100.0.109), internal only, authoritative"
    echo "Server=http://10.100.0.109:8090/archlinux/\$repo/os/\$arch"
    echo
    cat "$out"
} >"$TARGET.new"
# rename, so pacman never reads a half-written list
mv -f "$TARGET.new" "$TARGET"

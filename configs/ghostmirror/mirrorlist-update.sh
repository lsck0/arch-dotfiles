#!/usr/bin/env bash
# temp dir: ghostmirror's rename into root-owned /etc/pacman.d fails but still exits 0

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

cat "$out" >"$TARGET"

#!/usr/bin/env bash
set -euo pipefail

tmp=$(mktemp --suffix .rs)

cat > "$tmp"

cargo sort-derives --path "$tmp" --order "Debug,Default,Clone,Copy,PartialEq,Eq,PartialOrd,Ord,Hash,Serialize,Deserialize,..."

cat "$tmp"

rm "$tmp"

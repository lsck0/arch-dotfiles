#!/usr/bin/env bash
# stdin->stdout filter: reorder a Rust file's #[derive(...)] lists into canonical order.

set -euo pipefail

tmp=$(mktemp --suffix .rs)
# cargo sort-derives rewrites in place, so a failure mid-run must not leak the scratch file
trap 'rm -f "$tmp"' EXIT

cat > "$tmp"

cargo sort-derives --path "$tmp" --order "Debug,Default,Clone,Copy,PartialEq,Eq,PartialOrd,Ord,Hash,Serialize,Deserialize,..."

cat "$tmp"

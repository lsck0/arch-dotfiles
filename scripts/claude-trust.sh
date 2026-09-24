#!/usr/bin/env bash
# Mark a directory trusted for Claude Code, so `claude` skips the workspace trust dialog there.

set -euo pipefail

dir="$(realpath "${1:?dir}")"
f="$HOME/.claude.json"

[[ -f "$f" ]] || echo '{}' > "$f"

tmp="$(mktemp)"
jq --arg d "$dir" '
  .projects //= {}
  | .projects[$d] = ((.projects[$d] // {}) + {hasTrustDialogAccepted: true})
' "$f" > "$tmp" && mv "$tmp" "$f"

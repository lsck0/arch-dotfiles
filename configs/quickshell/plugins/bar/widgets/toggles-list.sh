#!/usr/bin/env bash
# json snapshot of toggles/toggle-*.sh for the Toggles panel
set -euo pipefail

# matches QS_DOTFILES_DIR in Commons/Paths.qml
TOGGLE_DIR="${QS_DOTFILES_DIR:-$HOME/projects/arch-dotfiles}/toggles"
cd "$TOGGLE_DIR"

entries="[]"
for script in toggle-*.sh; do
  name=$(basename "$script" .sh | sed 's/^toggle-//')
  raw=$("./$script" label)
  on=$("./$script" get)
  label=$(printf '%s' "$raw" | sed -E 's/^[●○] //; s/ \((on|off)\)$//')
  # n-state toggles: any non-default state counts as on
  entry=$(jq -nc --arg name "$name" --arg label "$label" --argjson on "$([[ -n "$on" && "$on" != off && "$on" != balanced ]] && echo true || echo false)" \
    '{name: $name, label: $label, on: $on}')
  entries=$(jq -c --argjson e "$entry" '. + [$e]' <<<"$entries")
done

printf '%s\n' "$entries"

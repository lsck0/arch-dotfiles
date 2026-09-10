#!/usr/bin/env bash
# JSON snapshot of every toggles/toggle-*.sh for Toggles.qml's hover panel —
# same discovery + `label`/`get` contract toggles/menu.sh uses, just
# rendered inline instead of shelling out to walker/fzf.
set -euo pipefail

TOGGLE_DIR="$HOME/projects/arch-dotfiles/toggles"
cd "$TOGGLE_DIR"

entries="[]"
for script in toggle-*.sh; do
  name=$(basename "$script" .sh | sed 's/^toggle-//')
  raw=$("./$script" label)
  on=$("./$script" get)
  label=$(printf '%s' "$raw" | sed -E 's/^[●○] //; s/ \((on|off)\)$//')
  # binary toggles report get as literal on/off; n-state ones (e.g.
  # toggle-powermode.sh) report their state name instead, or an empty
  # string when no override is forced (auto/hardware default) — "on" here
  # means "away from the off/default state" either way
  entry=$(jq -nc --arg name "$name" --arg label "$label" --argjson on "$([[ -n "$on" && "$on" != off && "$on" != balanced ]] && echo true || echo false)" \
    '{name: $name, label: $label, on: $on}')
  entries=$(jq -c --argjson e "$entry" '. + [$e]' <<<"$entries")
done

printf '%s\n' "$entries"

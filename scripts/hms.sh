#!/usr/bin/env bash
# hms ("herdr session manager", matching tms's naming pattern)
#
set -euo pipefail

TMS_CONFIG="$HOME/.config/tms/config.toml"

mapfile -t dirs < <(awk '
  /^\[\[search_dirs\]\]/ { path=""; depth=10; next }
  /^path[[:space:]]*=/ { gsub(/.*=[[:space:]]*"|"[[:space:]]*$/, ""); path=$0 }
  /^depth[[:space:]]*=/ { gsub(/.*=[[:space:]]*/, ""); depth=$0; print path "\t" depth }
' "$TMS_CONFIG")

repos=()
for entry in "${dirs[@]}"; do
  path="${entry%%$'\t'*}"
  depth="${entry##*$'\t'}"
  [[ -d "$path" ]] || continue
  while IFS= read -r gitdir; do
    full="$(dirname "$gitdir")"
    display="${full#"$path"/}"
    repos+=("$display"$'\t'"$full")
  done < <(fd --type d --hidden --no-ignore --max-depth "$depth" '^\.git$' "$path" 2>/dev/null)
done

[[ ${#repos[@]} -gt 0 ]] || { echo "no git repos found under tms search_dirs" >&2; exit 1; }

selected_line=$(printf '%s\n' "${repos[@]}" | sort -u -t$'\t' -k1,1 \
  | fzf --prompt="> " --delimiter=$'\t' --with-nth=1)
[[ -n "$selected_line" ]] || exit 0

selected="${selected_line#*$'\t'}"

label=$(basename "$selected")

existing_id=$(herdr workspace list 2>/dev/null \
  | jq -r --arg label "$label" '.result.workspaces[] | select(.label == $label) | .workspace_id' \
  | head -n1)

if [[ -n "$existing_id" ]]; then
  herdr workspace focus "$existing_id" >/dev/null
else
  herdr workspace create --cwd "$selected" --label "$label" --focus >/dev/null
fi

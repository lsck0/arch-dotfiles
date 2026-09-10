#!/usr/bin/env bash
# hms ("herdr session manager", matching tms's naming pattern): tmux-
# sessionizer-style project picker, native to herdr — fuzzy-find a git
# repo root under the same search paths as `tms` (~/.config/tms/config.toml,
# one source of truth for both tools), then focus an existing herdr workspace
# labeled after that repo or create a new one there. No nested tmux session —
# unlike the old `tms` popup, this drives herdr's own workspace model
# directly over its socket API (`herdr workspace ...`).
set -euo pipefail

TMS_CONFIG="$HOME/.config/tms/config.toml"

# Parse tms's `[[search_dirs]] path = "..." depth = N` array-of-tables. Small
# enough to not warrant a real TOML parser.
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
    # Display relative to this search dir's root (matches tms: "arch-dotfiles",
    # not "/home/luca/projects/arch-dotfiles"), tab-paired with the full path
    # so the actual `herdr workspace create --cwd` still gets an absolute one.
    display="${full#"$path"/}"
    repos+=("$display"$'\t'"$full")
  done < <(fd --type d --hidden --no-ignore --max-depth "$depth" '^\.git$' "$path" 2>/dev/null)
done

[[ ${#repos[@]} -gt 0 ]] || { echo "no git repos found under tms search_dirs" >&2; exit 1; }

selected_line=$(printf '%s\n' "${repos[@]}" | sort -u -t$'\t' -k1,1 \
  | fzf --prompt="herdr workspace > " --delimiter=$'\t' --with-nth=1)
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

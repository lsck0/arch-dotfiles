#!/usr/bin/env bash
# hms ("herdr session manager", matching tms's naming pattern)

set -euo pipefail

TMS_CONFIG="$HOME/.config/tms/config.toml"

mapfile -t dirs < <(awk '
  /^\[\[search_dirs\]\]/ { path=""; depth=10; next }
  /^path[[:space:]]*=/ { gsub(/.*=[[:space:]]*"|"*[[:space:]]*$/, ""); path=$0 }
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

# one herdr session (default) with a workspace per repo
if ! herdr status server 2>/dev/null | grep -q "status: running"; then
  cd "$selected"
  exec herdr
fi

existing_id=$(herdr workspace list 2>/dev/null \
  | jq -r --arg label "$label" '.result.workspaces[] | select(.label == $label) | .workspace_id' \
  | head -n1)

# A fresh workspace opens three tabs: 1 nvim, 2 claude, 3 zsh. herdr has no
# on-create hook, so lay them out here, the one place workspaces are born.
# (The cold-start `exec herdr` branch above can't: herdr makes that first
# workspace itself. Re-run hms to get a laid-out one.)
setup_tabs() {
  local ws="$1" created="$2" p1 t1 tab
  p1=$(jq -r '.result.root_pane.pane_id' <<<"$created")
  t1=$(jq -r '.result.tab.tab_id' <<<"$created")
  herdr pane run "$p1" nvim >/dev/null
  herdr tab rename "$t1" nvim >/dev/null
  for app in claude zsh; do
    tab=$(herdr tab create --workspace "$ws" --cwd "$selected" --no-focus)
    herdr tab rename "$(jq -r '.result.tab.tab_id' <<<"$tab")" "$app" >/dev/null
    pane=$(jq -r '.result.root_pane.pane_id' <<<"$tab")
    # zsh is the tab's default shell already; only claude needs launching
    if [[ "$app" == claude ]]; then
      herdr pane run "$pane" claude --permission-mode auto >/dev/null
    fi
  done
  herdr tab focus "$t1" >/dev/null
}

if [[ -n "$existing_id" ]]; then
  herdr workspace focus "$existing_id" >/dev/null
else
  created=$(herdr workspace create --cwd "$selected" --label "$label" --focus)
  setup_tabs "$(jq -r '.result.workspace.workspace_id' <<<"$created")" "$created"
fi

# outside herdr: attach a client (extra clients are fine)
[[ -n "${HERDR_ENV:-}" ]] || exec herdr

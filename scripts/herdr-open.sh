#!/usr/bin/env bash
# Focus a herdr workspace for <dir> labelled <label>, or create it laid out as three tabs: 1 nvim, 2 claude, 3 zsh.

set -euo pipefail

selected="${1:?dir}"
label="${2:-$(basename "$selected")}"

existing_id=$(herdr workspace list 2>/dev/null \
  | jq -r --arg label "$label" '.result.workspaces[] | select(.label == $label) | .workspace_id' \
  | head -n1)

if [[ -n "$existing_id" ]]; then
  herdr workspace focus "$existing_id" >/dev/null
  exit 0
fi

created=$(herdr workspace create --cwd "$selected" --label "$label" --focus)
ws=$(jq -r '.result.workspace.workspace_id' <<<"$created")
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
    claude-trust "$selected"   # skip the workspace trust dialog for this repo
    herdr pane run "$pane" claude --permission-mode auto >/dev/null
  fi
done
herdr tab focus "$t1" >/dev/null

#!/usr/bin/env bash
# Focus a herdr workspace for <dir> labelled <label>, or create it laid out as three tabs: 1 nvim, 2 claude, 3 zsh.

set -euo pipefail

selected="${1:?dir}"
label="${2:-$(basename "$selected")}"

# wait for the prompt: herdr pane run drops keystrokes typed before direnv/devenv is ready
# the timeout covers a cold devenv build (nix), which a first session hits
wait_prompt() {
  # anchored to end-of-line so a stray mid-output glyph does not match early
  herdr pane wait-output --regex '(λ|❯|[$%#])[[:space:]]*$' --timeout 600000 "$1" >/dev/null 2>&1
}

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

# only run once the prompt is confirmed, so the command is never typed into a shell still loading
if wait_prompt "$p1"; then herdr pane run "$p1" env NVIM_TMS=1 nvim >/dev/null; fi
herdr tab rename "$t1" nvim >/dev/null
for app in claude zsh; do
  tab=$(herdr tab create --workspace "$ws" --cwd "$selected" --no-focus)
  herdr tab rename "$(jq -r '.result.tab.tab_id' <<<"$tab")" "$app" >/dev/null
  pane=$(jq -r '.result.root_pane.pane_id' <<<"$tab")
  # zsh is the tab's default shell already; only claude needs launching
  if [[ "$app" == claude ]]; then
    if wait_prompt "$pane"; then herdr pane run "$pane" claude >/dev/null; fi
  fi
done
herdr tab focus "$t1" >/dev/null

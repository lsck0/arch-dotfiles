#!/usr/bin/env bash
# hms ("herdr session manager", matching tms's naming pattern)
#
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

# Issue 9: hms and tms picker theming must be identical. tms gets its picker
# colours from ~/.config/tms/config.toml (written by configs/tmux/link.sh from
# the same ~/.cache/wal/colors.json at link time); hms reads the same file here
# at runtime so both pickers track the wallpaper with one source of truth.
# Palette mirrors configs/tmux/tmux.conf's sourced colors-tmux.conf roles:
# selection = mode-style (bg color4, fg background), border = popup-border-style
# (color1), prompt/info = status-style fg / accent.
WAL_JSON="$HOME/.cache/wal/colors.json"
if [[ -f "$WAL_JSON" ]] && command -v jq >/dev/null 2>&1; then
  c_bg=$(jq -r '.special.background' "$WAL_JSON")
  c_fg=$(jq -r '.special.foreground' "$WAL_JSON")
  c_sel=$(jq -r '.colors.color4' "$WAL_JSON")
  c_border=$(jq -r '.colors.color1' "$WAL_JSON")
  c_accent=$(jq -r '.colors.color3' "$WAL_JSON")
  fzf_theme=(--color="fg:$c_fg,bg:$c_bg,hl:$c_border,fg+:$c_fg,bg+:$c_sel,hl+:$c_bg,"
    --color="info:$c_fg,prompt:$c_sel,pointer:$c_accent,marker:$c_accent,border:$c_border")
else
  fzf_theme=()
fi

selected_line=$(printf '%s\n' "${repos[@]}" | sort -u -t$'\t' -k1,1 \
  | fzf --prompt="> " --delimiter=$'\t' --with-nth=1 "${fzf_theme[@]}")
[[ -n "$selected_line" ]] || exit 0

selected="${selected_line#*$'\t'}"

label=$(basename "$selected")

# Issue 9: running hms from outside herdr (bare zsh popup, plain terminal) used
# to die with exit 1 — `herdr workspace list` fails with no server, and with
# pipefail + set -e that aborted the whole script before any attach happened.
#
# NOTE: `herdr status` exits 0 EVEN when the server is down (verified 0.8.2:
# "status: not running" still exits 0) — the exit code can't be the guard.
# Parse the server status line instead.
if herdr status server 2>/dev/null | grep -q "status: running"; then
  existing_id=$(herdr workspace list 2>/dev/null \
    | jq -r --arg label "$label" '.result.workspaces[] | select(.label == $label) | .workspace_id' \
    | head -n1)

  if [[ -n "$existing_id" ]]; then
    herdr workspace focus "$existing_id" >/dev/null
  else
    herdr workspace create --cwd "$selected" --label "$label" --focus >/dev/null
  fi
else
  # No server running (hms used from a bare shell / the zsh popup outside
  # herdr): `herdr --session <name>` is attach-or-create, tmux
  # new-session -A -s semantics — starts the server if needed, which is what
  # "hms should open a new herdr session if none exists" means. NOTE: --cwd
  # is only a per-subcommand flag (herdr workspace create / pane split), NOT
  # a global option — verified against 0.8.2 ("unknown option: --cwd") — so
  # the pane starts in whatever directory hms was invoked from rather than
  # the selected repo.
  exec herdr --session "$label"
fi

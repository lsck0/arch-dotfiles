#!/usr/bin/env bash
# hms ("herdr session manager", matching tms's naming pattern)

set -euo pipefail

TMS_CONFIG="$HOME/.config/tms/config.toml"

mapfile -t dirs < <(awk '
  function flush() { if (path != "") print path "\t" depth }
  /^\[\[search_dirs\]\]/ { flush(); path=""; depth=10; next }
  /^path[[:space:]]*=/ { gsub(/.*=[[:space:]]*"|"*[[:space:]]*$/, ""); path=$0 }
  /^depth[[:space:]]*=/ { gsub(/.*=[[:space:]]*/, ""); depth=$0 }
  END { flush() }
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
    # exclude nested package/vendor repos (emacs elpa, node_modules, cargo) so the
    # list matches tms: real projects only, not dependency checkouts.
  done < <(fd --type d --hidden --no-ignore --max-depth "$depth" \
    --exclude elpa --exclude node_modules --exclude .cargo --exclude vendor --exclude target \
    '^\.git$' "$path" 2>/dev/null)
done

[[ ${#repos[@]} -gt 0 ]] || { echo "no git repos found under tms search_dirs" >&2; exit 1; }

# Match tms's ratatui picker: its picker_colors are named ANSI colors (highlight
# LightBlue=12, highlight_text Black=0, info LightYellow=11, prompt LightGreen=10),
# so use the same ANSI indices (both resolve through the terminal palette). No fzf
# border or margin: herdr runs hms in a popup that already draws the frame, so a
# fzf border would double it. No pointer/marker glyph: selection is the highlight bg.
selected_line=$(printf '%s\n' "${repos[@]}" | sort -u -t$'\t' -k1,1 \
  | fzf --prompt="> " --delimiter=$'\t' --with-nth=1 \
        --border=none --no-scrollbar --pointer=' ' --marker=' ' --gutter=' ' \
        --color='fg:-1,bg:-1,fg+:0,bg+:12,hl:12,hl+:0,info:11,prompt:10,gutter:-1')
[[ -n "$selected_line" ]] || exit 0

selected="${selected_line#*$'\t'}"

label=$(basename "$selected")

# Cold start: bring up the headless server first, then build the labelled
# workspace, so hms works even with no herdr instance already running.
if ! herdr status server 2>/dev/null | grep -q "status: running"; then
  setsid -f herdr server >/dev/null 2>&1
  for _ in $(seq 1 100); do
    herdr status server 2>/dev/null | grep -q "status: running" && break
    sleep 0.1
  done
  herdr status server 2>/dev/null | grep -q "status: running" \
    || { echo "hms: herdr server failed to start within 10s" >&2; exit 1; }
fi

# Focus or create the workspace, laid out as 1 nvim, 2 claude, 3 zsh.
herdr-open "$selected" "$label"

# outside herdr: attach a client (extra clients are fine)
[[ -n "${HERDR_ENV:-}" ]] || exec herdr

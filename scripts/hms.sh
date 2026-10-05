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
  while IFS= read -r git; do
    # a .git file is a project only as a linked worktree, so submodules and the `gitdir: ./.bare` root stay out
    if [[ -f "$git" ]]; then
      read -r line <"$git" || true
      [[ "$line" =~ ^gitdir:\ .*/worktrees/[^/]+/?$ ]] || continue
    fi
    full="$(dirname "$git")"
    display="${full#"$path"/}"
    repos+=("$display"$'\t'"$full")
    # exclude nested package/vendor repos so the list is real projects only
  done < <(fd --type d --type f --hidden --no-ignore --max-depth "$depth" \
    --exclude elpa --exclude node_modules --exclude .cargo --exclude vendor --exclude target \
    '^\.git$' "$path" 2>/dev/null)
done

[[ ${#repos[@]} -gt 0 ]] || { echo "no git repos found under tms search_dirs" >&2; exit 1; }

# ansi indices match tms's picker_colors; herdr popup already draws the frame so no fzf border
selected_line=$(printf '%s\n' "${repos[@]}" | sort -u -t$'\t' -k1,1 \
  | fzf --prompt="> " --delimiter=$'\t' --with-nth=1 \
        --border=none --no-scrollbar --pointer=' ' --marker=' ' --gutter=' ' \
        --color='fg:-1,bg:-1,fg+:0,bg+:12,hl:12,hl+:0,info:11,prompt:10,gutter:-1')
[[ -n "$selected_line" ]] || exit 0

selected="${selected_line#*$'\t'}"

label=$(basename "$selected")

# cold start: bring up the headless server first so hms works with none running
if ! herdr status server 2>/dev/null | grep -q "status: running"; then
  setsid -f herdr server >/dev/null 2>&1
  for _ in $(seq 1 100); do
    herdr status server 2>/dev/null | grep -q "status: running" && break
    sleep 0.1
  done
  herdr status server 2>/dev/null | grep -q "status: running" \
    || { echo "hms: herdr server failed to start within 10s" >&2; exit 1; }
fi

herdr-open "$selected" "$label"

# outside herdr: attach a client (extra clients are fine)
[[ -n "${HERDR_ENV:-}" ]] || exec herdr

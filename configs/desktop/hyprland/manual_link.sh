#!/usr/bin/env bash

if ! command -v hyprpm >/dev/null 2>&1; then
    exit 0
fi

set -x

exec > >(tee -a "$HOME/.local/state/hypr-manual-link.log") 2>&1

# url|name as hyprpm lists it (case differs); only enabled plugins, every hyprland update rebuilds each added repo
REPOS=(
    "https://github.com/virtcode/hypr-dynamic-cursors|dynamic-cursors"
)

# headers first: `hyprpm add` refuses to build without them
STATE="$HOME/.local/state/hypr-plugins-built-for"
commit=$(hyprctl version -j 2>/dev/null | jq -r '.commit // empty')
# a rebuild or a fresh add must be re-enabled and reloaded into the running session
changed=0
if [[ -z "$commit" || "$(cat "$STATE" 2>/dev/null)" != "$commit" ]]; then
    if yes | hyprpm update -f; then
        mkdir -p "$(dirname "$STATE")"
        printf '%s\n' "$commit" > "$STATE"
        changed=1
    fi
fi

listed=$(hyprpm list 2>/dev/null)

for entry in "${REPOS[@]}"; do
    url="${entry%%|*}"; name="${entry##*|}"
    # re-adding an existing repo is a hard error
    if grep -qiF "Repository $name " <<<"$listed"; then
        continue
    fi
    yes | hyprpm add "$url" || true
    changed=1
done

# a normal login already has the plugin loaded, skip the reload then
if [[ "$changed" == 1 ]] || ! hyprctl plugin list 2>/dev/null | grep -qi dynamic-cursors; then
    hyprpm enable dynamic-cursors || true
    hyprpm reload
fi

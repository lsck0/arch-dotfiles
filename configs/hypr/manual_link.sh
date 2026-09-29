#!/usr/bin/env bash

if ! command -v hyprpm >/dev/null 2>&1; then
    exit 0
fi

set -x

exec > >(tee -a "$HOME/.local/state/hypr-manual-link.log") 2>&1

# url|name as hyprpm lists it (case differs)
REPOS=(
    "https://github.com/hyprnux/hyprglass|HyprGlass"
    "https://github.com/hyprwm/hyprland-plugins|hyprland-plugins"
    "https://github.com/outfoxxed/hy3|hy3"
    "https://github.com/virtcode/hypr-dynamic-cursors|dynamic-cursors"
    "https://github.com/KZDKM/Hyprspace|Hyprspace"
)

# headers first: `hyprpm add` refuses to build without them
STATE="$HOME/.local/state/hypr-plugins-built-for"
commit=$(hyprctl version -j 2>/dev/null | jq -r '.commit // empty')
if [[ -z "$commit" || "$(cat "$STATE" 2>/dev/null)" != "$commit" ]]; then
    if yes | hyprpm update -f; then
        mkdir -p "$(dirname "$STATE")"
        printf '%s\n' "$commit" > "$STATE"
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
done

hyprpm enable dynamic-cursors || true
hyprpm enable Hyprspace || true

hyprpm reload

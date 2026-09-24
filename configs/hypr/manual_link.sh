#!/usr/bin/env bash
# Registers the hyprpm plugin repos and loads them into the running compositor.

if ! command -v hyprpm >/dev/null 2>&1; then
    exit 0
fi

set -x

exec > >(tee -a "$HOME/.local/state/hypr-manual-link.log") 2>&1

# hyprpm serialises on a single lock, so a second hyprpm running concurrently just fails.

# url -> the repo name hyprpm lists it under (they differ in case for some).
REPOS=(
    "https://github.com/hyprnux/hyprglass|HyprGlass"
    "https://github.com/hyprwm/hyprland-plugins|hyprland-plugins"
    "https://github.com/outfoxxed/hy3|hy3"
    "https://github.com/virtcode/hypr-dynamic-cursors|dynamic-cursors"
    "https://github.com/KZDKM/Hyprspace|Hyprspace"
)

# Headers first: `hyprpm add` refuses to build without them.
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
    # Re-adding an existing repo is a hard error; `add` also builds the plugin.
    if grep -qiF "Repository $name " <<<"$listed"; then
        continue
    fi
    yes | hyprpm add "$url" || true
done

# Idempotent; enabling an already-enabled plugin is a no-op.
hyprpm enable dynamic-cursors || true
hyprpm enable Hyprspace || true

# Actually loads the enabled plugins into the running compositor.
hyprpm reload

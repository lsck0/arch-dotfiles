#!/usr/bin/env bash
# Registers the hyprpm plugin repos and loads them into the running compositor.
# Launched from hyprland_autostart.lua on every Hyprland start.

if ! command -v hyprpm >/dev/null 2>&1; then
    exit 0
fi

set -x

exec > >(tee -a "$HOME/.local/state/hypr-manual-link.log") 2>&1

# hyprpm serialises on a single lock, so a second hyprpm running concurrently
# just fails. This script is therefore the only place that talks to hyprpm:
# the compositor-wide `hyprpm reload` at the end of it replaces the separate
# one that used to sit in hyprland_autostart.lua and raced this script, which
# is why no plugin was ever actually loaded.

# url -> the repo name hyprpm lists it under (they differ in case for some).
REPOS=(
    "https://github.com/hyprnux/hyprglass|HyprGlass"
    "https://github.com/hyprwm/hyprland-plugins|hyprland-plugins"
    "https://github.com/outfoxxed/hy3|hy3"
    "https://github.com/virtcode/hypr-dynamic-cursors|dynamic-cursors"
    "https://github.com/KZDKM/Hyprspace|Hyprspace"
)

listed=$(hyprpm list 2>/dev/null)

added=0
for entry in "${REPOS[@]}"; do
    url="${entry%%|*}"; name="${entry##*|}"
    # Re-adding an existing repo is a hard error, and re-cloning every repo on
    # every boot took long enough that a logout could land mid-run — which is
    # how this script kept dying before it reached its own completion marker.
    if grep -qiF "Repository $name " <<<"$listed"; then
        continue
    fi
    yes | hyprpm add "$url" || true
    added=1
done

# `hyprpm update` rebuilds every plugin against the current Hyprland headers.
# It is minutes of compilation, so it runs only when the compositor's commit
# changed since the last successful run (or when a repo was just added), not
# on every boot.
STATE="$HOME/.local/state/hypr-plugins-built-for"
commit=$(hyprctl version -j 2>/dev/null | jq -r '.commit // empty')
if [[ -z "$commit" || "$added" == 1 || "$(cat "$STATE" 2>/dev/null)" != "$commit" ]]; then
    if yes | hyprpm update -f; then
        mkdir -p "$(dirname "$STATE")"
        printf '%s\n' "$commit" > "$STATE"
    fi
fi

# Idempotent; enabling an already-enabled plugin is a no-op.
hyprpm enable dynamic-cursors || true
hyprpm enable Hyprspace || true

# Actually loads the enabled plugins into the running compositor. Without this
# the `plugin { dynamic_cursors { ... } }` block in hyprland_plugins.lua is
# skipped at config parse, because its `hl.plugin` gate only fires for plugins
# that are already loaded.
hyprpm reload

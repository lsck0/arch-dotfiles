#!/usr/bin/env bash

if ! command -v hyprpm >/dev/null 2>&1; then
    exit 0
fi

MARKER="$HOME/.local/state/hypr-manual-link.done"
if [[ -e "$MARKER" ]]; then
    exit 0
fi

set -x

yes | hyprpm update -f

yes | hyprpm add https://github.com/hyprnux/hyprglass
yes | hyprpm add https://github.com/hyprwm/hyprland-plugins
yes | hyprpm add https://github.com/outfoxxed/hy3
yes | hyprpm add https://github.com/virtcode/hypr-dynamic-cursors
yes | hyprpm add https://github.com/KZDKM/Hyprspace

hyprpm enable dynamic-cursors || true
hyprpm enable Hyprspace || true

mkdir -p "$(dirname "$MARKER")"
touch "$MARKER"

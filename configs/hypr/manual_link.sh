#!/usr/bin/env bash
# Runs once on the first-ever Hyprland start (guarded by a state marker),
# then never again. Invoked from configs/hyprland/hyprland_autostart.lua.

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
# Hyprspace lives in its own repo, separate from hyprwm/hyprland-plugins
# (which only ships borders-plus-plus/csgo-vulkan-fix/hyprbars/hyprfocus) --
# `hyprpm enable Hyprspace` below always failed with "missing?" because this
# add was never here. With `set -e` that failure aborted the script before
# reaching the marker touch, so this whole block re-ran on every restart.
yes | hyprpm add https://github.com/KZDKM/Hyprspace

# `|| true`: a plugin enable can legitimately fail (build error, e.g. hy3
# currently fails to build on this Hyprland version -- see `hyprpm list`)
# without that blocking the marker below. This is first-boot-only setup;
# a broken plugin build is a real bug to chase separately, not something
# that should keep re-attempting a full update+add+enable pass every
# Hyprland restart forever.
hyprpm enable dynamic-cursors || true
hyprpm enable Hyprspace || true

mkdir -p "$(dirname "$MARKER")"
touch "$MARKER"

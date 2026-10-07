#!/usr/bin/env bash

# prop set silently no-ops before init
if waydroid status 2>/dev/null | grep -q 'not initialized'; then
    echo "waydroid: not initialized, run 'waydroid init' as root, then rerun config.sh" >&2
    exit 0
fi

waydroid prop set persist.waydroid.multi_windows true
waydroid prop set persist.waydroid.cursor_on_subsurface true

# android-side settings live in the user's waydroid data, but `waydroid shell` needs root and link.sh never asks for it:
# printed for the user to run in a terminal
settings=(development_settings_enabled enable_freeform_support force_resizable_activities enable_sizecompat_freeform)
echo "waydroid: for freeform windows, with a session running ('waydroid session start'), run once as root:" >&2
for setting in "${settings[@]}"; do
    echo "    waydroid shell -- settings put global $setting 1" >&2
done

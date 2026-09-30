#!/usr/bin/env bash
cd "$(dirname "$(readlink -f "$0")")" || exit 1

if ! command -v waydroid >/dev/null 2>&1; then
    exit 0
fi

set -e

waydroid prop set persist.waydroid.multi_windows true
waydroid prop set persist.waydroid.cursor_on_subsurface true

# android-side settings need a running session
if waydroid status 2>/dev/null | grep -q "Session:[[:space:]]*RUNNING"; then
    waydroid shell -- settings put global development_settings_enabled 1
    waydroid shell -- settings put global enable_freeform_support 1
    waydroid shell -- settings put global force_resizable_activities 1
    waydroid shell -- settings put global enable_sizecompat_freeform 1
else
    echo "waydroid: session not running, Android-side settings skipped." >&2
    echo "waydroid: run 'waydroid session start', then re-run this script." >&2
fi

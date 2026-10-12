#!/usr/bin/env bash
# new profiles get the gtk (oomox/wal) theme from /usr/lib/chromium/initial_preferences; profiles that predate it keep
# classic, so force system_theme on them too. chromium rewrites Preferences on exit, so this lands only while it is closed
set -euo pipefail

style_profile() {
    local prefs="$1/Default/Preferences"
    [[ -f "$prefs" ]] || return 0
    json_update "$prefs" '.extensions.theme.system_theme = 1'
}

style_profile "${XDG_CONFIG_HOME:-$HOME/.config}/chromium"
profile_has work && style_profile "${XDG_DATA_HOME:-$HOME/.local/share}/capgemini/chromium" || true

# native wayland: pipewire screencast portal (screen share) works instead of xwayland, and 4k scales
desktop_override chromium.desktop 's|^Exec=chromium|Exec=chromium --ozone-platform-hint=auto|'

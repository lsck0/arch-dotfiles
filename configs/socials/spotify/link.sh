#!/usr/bin/env bash

THEMES="${HOME}/.config/spicetify/Themes"

fetch_git_pinned https://github.com/spicetify/spicetify-themes.git 33a08ea009687f5a42ff678015c28797fe142a7c "$THEMES"
link_into "${THEMES}/wal" color.ini user.css

# spicetify config needs the client
if ! pacman -Q spotify >/dev/null 2>&1; then
    echo "spotify: not installed, skipping spicetify" >&2
    exit 0
fi

# obs taps spotify before the loudness lanes, so normalize here (-14 lufs, no limiter); only while closed, exit rewrites prefs
if ! pgrep -x spotify >/dev/null; then
    for prefs in "${HOME}"/.config/spotify/Users/*/prefs; do
        [ -f "${prefs}" ] || continue
        sed -i '/^audio\.normalize_v2=/d; /^audio\.loudness\.environment=/d' "${prefs}"
        printf 'audio.normalize_v2=true\naudio.loudness.environment=1\n' >>"${prefs}"
    done
fi

spicetify config current_theme wal color_scheme pywal
spicetify config experimental_features 0
# on, it also strips the [dir=ltr] rules spotify spacing lives in
spicetify config remove_rtl_rule 0
spicetify config overwrite_assets 1

# blockthespot-style ad/telemetry block; `config extensions` toggles the list, so add it only when absent
link_into "${HOME}/.config/spicetify/Extensions" adblock.js
spicetify config extensions | tr '|' '\n' | grep -qx adblock.js || spicetify config extensions adblock.js

# spicetify patches a copy of the client in this home (hook/spicetify-apply.sh), the launcher starts that copy
desktop_override spotify.desktop "s|^Exec=spotify |Exec=$PWD/spotify-launch.sh |"
# permanent: the first login, every spotify upgrade (a fresh xpui.spa) and every login (an upgrade while logged out) reapply.
# now too, so this log shows it; a failed apply still arms the units
status=0
./hook/spicetify-apply.sh || status=$?
# prefs changes on first login; a fresh xpui.spa on upgrade (PathExists would loop while nobody is logged in yet).
# permanent, so the service is enabled at login too: an upgrade while this user was logged out fires no path unit
user_hook spicetify-apply --permanent \
    --watch "%h/.config/spotify/prefs" \
    --watch "/opt/spotify/Apps/xpui.spa"
exit "$status"

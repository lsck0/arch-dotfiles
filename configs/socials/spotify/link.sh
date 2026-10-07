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

# patching needs the wheel write access spotify/system.sh grants; without it the stock client stays
if [[ ! -w /opt/spotify || ! -w /opt/spotify/Apps ]]; then
    user_hook_retire spicetify-apply
    rm -f "${USER_HOOK_UNIT_DIR}/default.target.wants/spicetify-apply.service"
    exit 0
fi
# permanent: the first login, every spotify upgrade (a fresh xpui.spa) and every login (an upgrade while logged out) reapply.
# now too, so this log shows it; a failed apply still arms the units
status=0
./hook/spicetify-apply.sh || status=$?
user_hook_install ./hook spicetify-apply
systemctl --user enable spicetify-apply.service
exit "$status"

#!/usr/bin/env bash
cd "$(dirname "$(readlink -f "$0")")" || exit 1

set -e

source $DOTFILES/scripts/lib/fetch.sh
fetch_git_pinned https://github.com/spicetify/spicetify-themes.git 33a08ea009687f5a42ff678015c28797fe142a7c "${HOME}/.config/spicetify/Themes"

mkdir -p "${HOME}/.config/spicetify/Themes/wal"

ln -sfn "${PWD}/color.ini" "${HOME}/.config/spicetify/Themes/wal/color.ini"
ln -sfn "${PWD}/user.css" "${HOME}/.config/spicetify/Themes/wal/user.css"

# /opt/spotify only exists once spotify is installed, so gate everything below on it
if ! pacman -Q spotify >/dev/null 2>&1; then
    echo "spotify: not installed, skipping spicetify apply" >&2
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

# spicetify writes here, own it instead of 777
sudo chown -R "$USER" /opt/spotify /opt/spotify/Apps

spicetify config current_theme wal color_scheme pywal
spicetify config experimental_features 0
# on, it also strips the [dir=ltr] rules spotify spacing lives in
spicetify config remove_rtl_rule 0
spicetify config overwrite_assets 1

spicetify apply || spicetify backup apply

python3 "${PWD}/spicetify-unmap-classes.py"

# first apply waits for the first spotify login; later spotify updates come through the pacman hook
spotify_patched() { [[ -d /opt/spotify/Apps/xpui ]]; }
source $DOTFILES/scripts/lib/user-hook.sh
user_hook_oneshot ./hook spicetify-apply spotify_patched

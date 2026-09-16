#!/usr/bin/env bash
cd "$(dirname "$(readlink -f "$0")")" || exit 1

if ! command -v spicetify >/dev/null 2>&1; then
    exit 0
fi

set -ex

if [ ! -d ${HOME}/.config/spicetify/Themes/.git ]; then
    git clone --depth 1 https://github.com/spicetify/spicetify-themes.git ${HOME}/.config/spicetify/Themes/
fi

mkdir -p ${HOME}/.config/spicetify/Themes/wal
# pywal-spicetify panics unless pywal's template dir exists, even though wallust generates the colors.
mkdir -p ${HOME}/.config/wal/templates

ln -sfn ${PWD}/color.ini ${HOME}/.config/spicetify/Themes/wal/color.ini
ln -sfn ${PWD}/user.css ${HOME}/.config/spicetify/Themes/wal/user.css

sudo chmod 777 /opt/spotify
sudo chmod 777 /opt/spotify/Apps -R

spicetify config current_theme wal color_scheme pywal
spicetify config experimental_features 0
# On, it strips every [dir=ltr] rule too, and Spotify's spacing lives in those.
spicetify config remove_rtl_rule 0
spicetify config overwrite_assets 1

if ! pacman -Q spotify >/dev/null 2>&1; then
    echo "spotify: not installed, skipping spicetify apply" >&2
    exit 0
fi

spicetify apply || spicetify backup apply || true

python3 "${PWD}/spicetify-unmap-classes.py"

#!/bin/env bash

set -ex

if [ ! -d ${HOME}/.config/spicetify/Themes/.git ]; then
    git clone --depth=1 https://github.com/spicetify/spicetify-themes.git ${HOME}/.config/spicetify/Themes/
fi

mkdir -p ${HOME}/.config/spicetify/Themes/wal
ln -sf ${PWD}/color.ini ${HOME}/.config/spicetify/Themes/wal/
ln -sf ${PWD}/user.css ${HOME}/.config/spicetify/Themes/wal/

sudo chmod 777 /opt/spotify
sudo chmod 777 /opt/spotify/Apps -R

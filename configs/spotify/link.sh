#!/bin/env bash

set -ex

if [ ! -d ${HOME}/.config/spicetify/Themes/.git ]; then
    git clone --depth=1 https://github.com/spicetify/spicetify-themes.git ${HOME}/.config/spicetify/Themes/
fi

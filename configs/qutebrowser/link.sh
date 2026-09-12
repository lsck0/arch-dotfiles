#!/usr/bin/env bash

if ! command -v qutebrowser >/dev/null 2>&1; then
    exit 0
fi

set -ex

mkdir -p ${HOME}/.config/qutebrowser

ln -sf ${PWD}/config.py ${HOME}/.config/qutebrowser/config.py
ln -sf ${PWD}/startpage.html ${HOME}/.config/qutebrowser/startpage.html

#!/usr/bin/env bash

set -ex

mkdir -p ${HOME}/.config/qutebrowser
ln -sf ${PWD}/config.py ${HOME}/.config/qutebrowser/config.py
ln -sf ${PWD}/startpage.html ${HOME}/.config/qutebrowser/startpage.html

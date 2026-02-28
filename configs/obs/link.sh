#!/usr/bin/env bash

set -ex

mkdir -p ${HOME}/.config/obs-studio/basic/scenes/
mkdir -p ${HOME}/.config/obs-studio/basic/profiles/Untitled/

ln -sf ${PWD}/Untitled.json ${HOME}/.config/obs-studio/basic/scenes/Untitled.json
ln -sf ${PWD}/basic.ini ${HOME}/.config/obs-studio/basic/profiles/Untitled/basic.ini

#!/usr/bin/env bash

set -ex

mkdir -p ${HOME}/documents ${HOME}/downloads ${HOME}/music ${HOME}/pictures ${HOME}/videos ${HOME}/code
ln -sf ${PWD}/mimeapps.list ${HOME}/.config/mimeapps.list
ln -sf ${PWD}/user-dirs.dirs ${HOME}/.config/user-dirs.dirs

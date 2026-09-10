#!/usr/bin/env bash

set -ex

mkdir -p ${HOME}/desktop ${HOME}/documents ${HOME}/downloads ${HOME}/music ${HOME}/pictures ${HOME}/videos ${HOME}/projects
ln -sf ${PWD}/mimeapps.list ${HOME}/.config/mimeapps.list
ln -sf ${PWD}/user-dirs.dirs ${HOME}/.config/user-dirs.dirs

# Portal backend preference for the Hyprland session. Filename must match
# XDG_CURRENT_DESKTOP (Hyprland) lowercased.
mkdir -p ${HOME}/.config/xdg-desktop-portal
ln -sf ${PWD}/hyprland-portals.conf ${HOME}/.config/xdg-desktop-portal/hyprland-portals.conf

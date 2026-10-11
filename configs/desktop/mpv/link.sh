#!/usr/bin/env bash

command -v mpv >/dev/null 2>&1 || exit 0
link_into "$HOME/.config/mpv" mpv.conf
mkdir -p "$HOME/pictures/screenshots"

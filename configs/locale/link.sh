#!/usr/bin/env bash

if ! command -v locale-gen >/dev/null 2>&1; then
    exit 0
fi

set -e

sudo sed -i 's/^# *\(de_DE\.UTF-8 UTF-8\)/\1/' /etc/locale.gen
sudo sed -i 's/^# *\(en_US\.UTF-8 UTF-8\)/\1/' /etc/locale.gen

sudo locale-gen

# hyprland sets its own layout in hyprland_input.lua
if command -v localectl >/dev/null 2>&1; then
    sudo localectl set-keymap de-latin1-nodeadkeys
    sudo localectl set-x11-keymap de pc105 nodeadkeys ctrl:nocaps,terminate:ctrl_alt_bksp
fi

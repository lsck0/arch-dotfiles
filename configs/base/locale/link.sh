#!/usr/bin/env bash

source $DOTFILES/scripts/lib/personal.sh

set -e

# bootstrap.sh's console default, also what a guest who kept it gets
DEFAULT_KEYMAP=de-latin1

sudo sed -i 's/^# *\(de_DE\.UTF-8 UTF-8\)/\1/' /etc/locale.gen
sudo sed -i 's/^# *\(en_US\.UTF-8 UTF-8\)/\1/' /etc/locale.gen

[[ $(locale -a | grep -cxE 'de_DE\.utf8|en_US\.utf8') == 2 ]] || sudo locale-gen

# hyprland_input.lua keeps its own german layout and only takes a guest's x11 layout from here
if command -v localectl >/dev/null 2>&1; then
    # wsl has no vconsole.conf
    keymap=$(sed -n 's/^KEYMAP=//p' /etc/vconsole.conf 2>/dev/null || true)
    if is_personal || [[ "${keymap:-$DEFAULT_KEYMAP}" == "$DEFAULT_KEYMAP"* ]]; then
        sudo localectl set-keymap de-latin1-nodeadkeys
        sudo localectl set-x11-keymap de pc105 nodeadkeys ctrl:nocaps,terminate:ctrl_alt_bksp
    else
        # a guest's own keymap from bootstrap.sh; localectl derives the x11 layout plasma and hyprland use from it
        sudo localectl set-keymap "$keymap"
    fi
fi

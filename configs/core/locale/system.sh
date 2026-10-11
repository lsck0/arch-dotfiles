#!/usr/bin/env bash

# bootstrap.sh's console default, also what a guest machine that kept it has
DEFAULT_KEYMAP=de-latin1

sed -i 's/^# *\(de_DE\.UTF-8 UTF-8\)/\1/' /etc/locale.gen
sed -i 's/^# *\(en_US\.UTF-8 UTF-8\)/\1/' /etc/locale.gen

[[ $(locale -a | grep -cxE 'de_DE\.utf8|en_US\.utf8') == 2 ]] || locale-gen

# hyprland_input.lua keeps its own german layout and only takes another machine's x11 layout from here
if command -v localectl >/dev/null 2>&1; then
    # wsl has no vconsole.conf
    keymap=$(sed -n 's/^KEYMAP=//p' /etc/vconsole.conf 2>/dev/null || true)
    if [[ "${keymap:-$DEFAULT_KEYMAP}" == "$DEFAULT_KEYMAP"* ]]; then
        localectl set-keymap de-latin1-nodeadkeys
        localectl set-x11-keymap de pc105 nodeadkeys ctrl:nocaps,terminate:ctrl_alt_bksp
    else
        # the keymap bootstrap.sh asked for; localectl derives the x11 layout plasma and hyprland use from it
        localectl set-keymap "$keymap"
    fi
fi

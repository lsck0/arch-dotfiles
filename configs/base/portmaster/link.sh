#!/usr/bin/env bash

if [[ -f /etc/xdg/autostart/portmaster-autostart.desktop ]]; then
    link_into "${XDG_CONFIG_HOME:-$HOME/.config}/autostart" portmaster-autostart.desktop
fi
